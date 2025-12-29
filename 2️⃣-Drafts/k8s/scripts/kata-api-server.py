#!/usr/bin/env python3
"""
Kata Containers Management API Server

Exposes Kata VM operations (pause/resume/snapshot) via REST API.
Deploy as a DaemonSet on each node to manage local VMs.

Usage:
    python3 kata-api-server.py

API Endpoints:
    GET  /vms                    - List all Kata VMs
    GET  /vms/<pod>              - Get VM status
    POST /vms/<pod>/pause        - Pause VM
    POST /vms/<pod>/resume       - Resume VM
    POST /vms/<pod>/snapshot     - Create snapshot
    GET  /snapshots              - List snapshots
    POST /vms/<pod>/restore      - Restore from snapshot (requires new VM)
"""

import os
import json
import glob
import subprocess
import socket
from datetime import datetime
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# Configuration
LISTEN_HOST = os.environ.get('LISTEN_HOST', '0.0.0.0')
LISTEN_PORT = int(os.environ.get('LISTEN_PORT', '8080'))
SNAPSHOT_DIR = os.environ.get('SNAPSHOT_DIR', '/var/lib/kata-snapshots')
KATA_VM_DIR = '/run/vc/vm'

class KataVMManager:
    """Manages Kata Container VMs via hypervisor APIs"""

    def __init__(self):
        self.snapshot_dir = Path(SNAPSHOT_DIR)
        self.snapshot_dir.mkdir(parents=True, exist_ok=True)

    def _find_vms(self):
        """Find all running Kata VMs"""
        vms = []
        if not os.path.exists(KATA_VM_DIR):
            return vms

        for vm_dir in glob.glob(f'{KATA_VM_DIR}/*'):
            vm_id = os.path.basename(vm_dir)

            # Check for Cloud Hypervisor
            clh_sock = os.path.join(vm_dir, 'clh-api.sock')
            if os.path.exists(clh_sock):
                vms.append({
                    'vm_id': vm_id,
                    'hypervisor': 'cloud-hypervisor',
                    'socket': clh_sock
                })
                continue

            # Check for Firecracker
            fc_sock = os.path.join(vm_dir, 'api.socket')
            if os.path.exists(fc_sock):
                vms.append({
                    'vm_id': vm_id,
                    'hypervisor': 'firecracker',
                    'socket': fc_sock
                })
                continue

            # Check for QEMU (QMP socket)
            qmp_sock = os.path.join(vm_dir, 'qmp.sock')
            if os.path.exists(qmp_sock):
                vms.append({
                    'vm_id': vm_id,
                    'hypervisor': 'qemu',
                    'socket': qmp_sock
                })

        return vms

    def _get_pod_for_vm(self, vm_id):
        """Try to map VM ID to pod name via kubectl"""
        try:
            result = subprocess.run(
                ['kubectl', 'get', 'pods', '-A', '-o', 'json'],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                pods = json.loads(result.stdout)
                for pod in pods.get('items', []):
                    uid = pod['metadata'].get('uid', '').replace('-', '')
                    if vm_id.startswith(uid[:12]):
                        return {
                            'name': pod['metadata']['name'],
                            'namespace': pod['metadata']['namespace'],
                            'uid': pod['metadata']['uid']
                        }
        except Exception:
            pass
        return None

    def _curl_unix(self, socket_path, method, path, data=None):
        """Make HTTP request via Unix socket"""
        import http.client

        class UnixHTTPConnection(http.client.HTTPConnection):
            def __init__(self, socket_path):
                super().__init__('localhost')
                self.socket_path = socket_path

            def connect(self):
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self.socket_path)

        try:
            conn = UnixHTTPConnection(socket_path)
            headers = {'Content-Type': 'application/json'} if data else {}
            body = json.dumps(data) if data else None
            conn.request(method, path, body=body, headers=headers)
            response = conn.getresponse()
            return {
                'status': response.status,
                'body': response.read().decode('utf-8')
            }
        except Exception as e:
            return {'error': str(e)}

    def list_vms(self):
        """List all Kata VMs with their status"""
        vms = self._find_vms()
        result = []

        for vm in vms:
            info = {
                'vm_id': vm['vm_id'],
                'hypervisor': vm['hypervisor'],
                'state': 'unknown'
            }

            # Get pod info
            pod_info = self._get_pod_for_vm(vm['vm_id'])
            if pod_info:
                info['pod'] = pod_info

            # Get VM state
            if vm['hypervisor'] == 'cloud-hypervisor':
                resp = self._curl_unix(vm['socket'], 'GET', '/api/v1/vm.info')
                if 'body' in resp:
                    try:
                        vm_info = json.loads(resp['body'])
                        info['state'] = vm_info.get('state', 'unknown')
                        info['memory_mb'] = vm_info.get('config', {}).get('memory', {}).get('size', 0) // (1024*1024)
                    except:
                        pass

            elif vm['hypervisor'] == 'firecracker':
                resp = self._curl_unix(vm['socket'], 'GET', '/vm')
                if 'body' in resp:
                    try:
                        vm_info = json.loads(resp['body'])
                        info['state'] = vm_info.get('state', 'unknown')
                    except:
                        pass

            result.append(info)

        return result

    def get_vm(self, vm_id):
        """Get detailed info for a specific VM"""
        vms = self._find_vms()
        for vm in vms:
            if vm['vm_id'] == vm_id or vm['vm_id'].startswith(vm_id):
                info = {'vm_id': vm['vm_id'], 'hypervisor': vm['hypervisor']}

                if vm['hypervisor'] == 'cloud-hypervisor':
                    resp = self._curl_unix(vm['socket'], 'GET', '/api/v1/vm.info')
                    if 'body' in resp:
                        info['details'] = json.loads(resp['body'])

                pod_info = self._get_pod_for_vm(vm['vm_id'])
                if pod_info:
                    info['pod'] = pod_info

                return info

        return {'error': 'VM not found'}

    def pause_vm(self, vm_id):
        """Pause a VM"""
        vms = self._find_vms()
        for vm in vms:
            if vm['vm_id'] == vm_id or vm['vm_id'].startswith(vm_id):
                if vm['hypervisor'] == 'cloud-hypervisor':
                    resp = self._curl_unix(vm['socket'], 'PUT', '/api/v1/vm.pause')
                    return {'success': resp.get('status') == 204 or resp.get('status') == 200, 'response': resp}

                elif vm['hypervisor'] == 'firecracker':
                    resp = self._curl_unix(vm['socket'], 'PATCH', '/vm', {'state': 'Paused'})
                    return {'success': resp.get('status') == 204, 'response': resp}

        return {'error': 'VM not found'}

    def resume_vm(self, vm_id):
        """Resume a paused VM"""
        vms = self._find_vms()
        for vm in vms:
            if vm['vm_id'] == vm_id or vm['vm_id'].startswith(vm_id):
                if vm['hypervisor'] == 'cloud-hypervisor':
                    resp = self._curl_unix(vm['socket'], 'PUT', '/api/v1/vm.resume')
                    return {'success': resp.get('status') == 204 or resp.get('status') == 200, 'response': resp}

                elif vm['hypervisor'] == 'firecracker':
                    resp = self._curl_unix(vm['socket'], 'PATCH', '/vm', {'state': 'Resumed'})
                    return {'success': resp.get('status') == 204, 'response': resp}

        return {'error': 'VM not found'}

    def snapshot_vm(self, vm_id, name=None):
        """Create a snapshot of a VM (must be paused first)"""
        vms = self._find_vms()
        for vm in vms:
            if vm['vm_id'] == vm_id or vm['vm_id'].startswith(vm_id):
                # Generate snapshot name
                timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
                snap_name = name or f"snap-{vm_id[:12]}-{timestamp}"
                snap_path = self.snapshot_dir / snap_name
                snap_path.mkdir(parents=True, exist_ok=True)

                if vm['hypervisor'] == 'cloud-hypervisor':
                    resp = self._curl_unix(
                        vm['socket'], 'PUT', '/api/v1/vm.snapshot',
                        {'destination_url': f'file://{snap_path}'}
                    )

                    if resp.get('status') in [200, 204] or not resp.get('body'):
                        # Save metadata
                        meta = {
                            'vm_id': vm['vm_id'],
                            'hypervisor': vm['hypervisor'],
                            'timestamp': datetime.now().isoformat(),
                            'path': str(snap_path)
                        }
                        pod_info = self._get_pod_for_vm(vm['vm_id'])
                        if pod_info:
                            meta['pod'] = pod_info

                        with open(snap_path / 'metadata.json', 'w') as f:
                            json.dump(meta, f, indent=2)

                        return {'success': True, 'snapshot': snap_name, 'path': str(snap_path)}

                    return {'success': False, 'response': resp}

                elif vm['hypervisor'] == 'firecracker':
                    resp = self._curl_unix(
                        vm['socket'], 'PUT', '/snapshot/create',
                        {
                            'snapshot_type': 'Full',
                            'snapshot_path': str(snap_path / 'vmstate.snap'),
                            'mem_file_path': str(snap_path / 'memory.snap')
                        }
                    )
                    return {'success': resp.get('status') == 204, 'snapshot': snap_name, 'response': resp}

        return {'error': 'VM not found'}

    def list_snapshots(self):
        """List all snapshots"""
        snapshots = []
        for snap_dir in self.snapshot_dir.glob('snap-*'):
            if snap_dir.is_dir():
                meta_file = snap_dir / 'metadata.json'
                meta = {}
                if meta_file.exists():
                    with open(meta_file) as f:
                        meta = json.load(f)

                # Calculate size
                size = sum(f.stat().st_size for f in snap_dir.glob('*') if f.is_file())

                snapshots.append({
                    'name': snap_dir.name,
                    'path': str(snap_dir),
                    'size_mb': size // (1024*1024),
                    'metadata': meta
                })

        return snapshots


class KataAPIHandler(BaseHTTPRequestHandler):
    """HTTP request handler for Kata API"""

    manager = KataVMManager()

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/vms' or path == '/vms/':
            self._send_json(self.manager.list_vms())

        elif path.startswith('/vms/'):
            vm_id = path.split('/')[2]
            self._send_json(self.manager.get_vm(vm_id))

        elif path == '/snapshots' or path == '/snapshots/':
            self._send_json(self.manager.list_snapshots())

        elif path == '/health':
            self._send_json({'status': 'ok'})

        else:
            self._send_json({'error': 'Not found'}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        parts = path.strip('/').split('/')

        if len(parts) >= 3 and parts[0] == 'vms':
            vm_id = parts[1]
            action = parts[2]

            if action == 'pause':
                self._send_json(self.manager.pause_vm(vm_id))

            elif action == 'resume':
                self._send_json(self.manager.resume_vm(vm_id))

            elif action == 'snapshot':
                # Read optional name from body
                content_length = int(self.headers.get('Content-Length', 0))
                body = {}
                if content_length > 0:
                    body = json.loads(self.rfile.read(content_length))

                self._send_json(self.manager.snapshot_vm(vm_id, body.get('name')))

            else:
                self._send_json({'error': f'Unknown action: {action}'}, 400)
        else:
            self._send_json({'error': 'Not found'}, 404)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def log_message(self, format, *args):
        print(f"[{datetime.now().isoformat()}] {args[0]}")


def main():
    print(f"Starting Kata API Server on {LISTEN_HOST}:{LISTEN_PORT}")
    print(f"Snapshot directory: {SNAPSHOT_DIR}")
    print(f"Watching VM directory: {KATA_VM_DIR}")
    print()
    print("Endpoints:")
    print("  GET  /vms                - List VMs")
    print("  GET  /vms/<id>           - Get VM details")
    print("  POST /vms/<id>/pause     - Pause VM")
    print("  POST /vms/<id>/resume    - Resume VM")
    print("  POST /vms/<id>/snapshot  - Create snapshot")
    print("  GET  /snapshots          - List snapshots")
    print()

    server = HTTPServer((LISTEN_HOST, LISTEN_PORT), KataAPIHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
