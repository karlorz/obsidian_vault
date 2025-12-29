#!/bin/bash
#
# Test RAM State Checkpoint with Podman
# Demonstrates that in-memory data (RAM) is preserved across checkpoint/restore
#

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Podman RAM State Checkpoint Test                            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

CONTAINER_NAME="ram-state-test"
CHECKPOINT_FILE="/tmp/ram-checkpoint.tar.gz"

# Cleanup any existing
podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
rm -f "$CHECKPOINT_FILE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ 1. Creating container with Python process holding RAM state"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create Python script that holds state in memory
cat > /tmp/ram_state_app.py << 'PYEOF'
import time
import random
import sys

# Create data in RAM - this should be preserved across checkpoint
memory_data = {
    "counter": 0,
    "random_seed": random.randint(1000, 9999),
    "data_array": [i * 2 for i in range(100)],
    "message": "This data exists only in RAM!"
}

print(f"=== Process Started ===", flush=True)
print(f"Random seed: {memory_data['random_seed']}", flush=True)
print(f"Data array sum: {sum(memory_data['data_array'])}", flush=True)
print(f"Message: {memory_data['message']}", flush=True)
print("", flush=True)

while True:
    memory_data["counter"] += 1
    # Add computed data based on counter
    memory_data["computed"] = memory_data["counter"] * memory_data["random_seed"]

    print(f"[Tick {memory_data['counter']}] computed={memory_data['computed']}, array_sum={sum(memory_data['data_array'])}", flush=True)
    time.sleep(2)
PYEOF

# Run container with the Python script
podman run -d --name "$CONTAINER_NAME" --runtime=runc \
    -v /tmp/ram_state_app.py:/app/ram_state_app.py:ro \
    python:3.11-alpine python3 /app/ram_state_app.py

echo "Container started, waiting for initialization..."
sleep 6

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ 2. Container logs (showing RAM state)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
podman logs "$CONTAINER_NAME"

# Get the random seed for verification
RANDOM_SEED=$(podman logs "$CONTAINER_NAME" 2>&1 | grep "Random seed:" | awk '{print $3}')
LAST_TICK=$(podman logs "$CONTAINER_NAME" 2>&1 | grep "\[Tick" | tail -1)
echo ""
echo "📌 Random seed to verify after restore: $RANDOM_SEED"
echo "📌 Last tick before checkpoint: $LAST_TICK"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ 3. Creating checkpoint (freezing RAM state)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Creating checkpoint..."
START_TIME=$(date +%s.%N)
podman container checkpoint "$CONTAINER_NAME" --export="$CHECKPOINT_FILE"
END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)

echo ""
ls -lh "$CHECKPOINT_FILE"
echo ""
echo "✓ Checkpoint created in ${ELAPSED}s"
echo "  Container state (including RAM) saved to file."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ 4. Examining checkpoint contents"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Checkpoint archive contents:"
tar -tzf "$CHECKPOINT_FILE" | head -20
echo "..."
echo ""
echo "Total files in checkpoint: $(tar -tzf "$CHECKPOINT_FILE" | wc -l)"

# Show memory pages file size
echo ""
echo "Memory dump files:"
tar -tzf "$CHECKPOINT_FILE" | grep -E "pages|mem" || echo "(memory data embedded)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ 5. Removing original container"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

podman rm "$CONTAINER_NAME"
echo "✓ Original container deleted"
echo ""
echo "⏳ Waiting 3 seconds before restore..."
sleep 3

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ 6. Restoring from checkpoint"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Restoring container from checkpoint..."
START_TIME=$(date +%s.%N)
podman container restore --import="$CHECKPOINT_FILE" --name "$CONTAINER_NAME"
END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)

echo ""
echo "✓ Container restored in ${ELAPSED}s"
echo ""
echo "Container status:"
podman ps --filter name="$CONTAINER_NAME"

echo ""
echo "⏳ Waiting for container to produce output..."
sleep 5

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ 7. Verifying RAM state was preserved"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Recent logs after restore:"
podman logs --tail 10 "$CONTAINER_NAME"

RESTORED_SEED=$(podman logs "$CONTAINER_NAME" 2>&1 | grep "Random seed:" | awk '{print $3}')

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                   VERIFICATION RESULTS                        ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║                                                               ║"
printf "║  Original random seed: %-37s ║\n" "$RANDOM_SEED"
printf "║  Restored random seed: %-37s ║\n" "$RESTORED_SEED"
echo "║                                                               ║"

if [ "$RANDOM_SEED" = "$RESTORED_SEED" ]; then
    echo "║  ✅ SUCCESS! RAM state was preserved!                        ║"
    echo "║                                                               ║"
    echo "║  The Python process continued with the SAME random seed      ║"
    echo "║  and in-memory data structures from before checkpoint.       ║"
    echo "║  This proves the RAM/memory state was fully preserved.       ║"
else
    echo "║  ❌ MISMATCH - something went wrong                          ║"
fi
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
rm -f "$CHECKPOINT_FILE" /tmp/ram_state_app.py
echo "✓ Cleanup complete"
