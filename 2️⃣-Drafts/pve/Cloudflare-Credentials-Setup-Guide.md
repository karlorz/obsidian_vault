# Cloudflare Credentials Setup Guide

Guide for setting up Cloudflare environment variables for PVE LXC sandbox tunnel integration.

---

## Required Environment Variables

```bash
export CF_API_TOKEN="your-api-token"
export CF_ZONE_ID="your-zone-id"
export CF_ACCOUNT_ID="your-account-id"
export CF_DOMAIN="yourdomain.com"
```

---

## 1. CF_ACCOUNT_ID & CF_ZONE_ID

**Official docs:** [Find account and zone IDs](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/)

### Steps:
1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain from the list
3. On the **Overview** page, scroll down to the right sidebar
4. Look for the **API** section:
   - **Zone ID** - Click to copy
   - **Account ID** - Click to copy

```
+----------------------------------+
|  API                             |
|  --------------------------------|
|  Zone ID                         |
|  [abc123def456...]  [Copy]       |
|                                  |
|  Account ID                      |
|  [xyz789ghi012...]  [Copy]       |
+----------------------------------+
```

---

## 2. CF_API_TOKEN

**Official docs:** [Create API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)

### Steps:

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Click your **profile icon** (top right) -> **My Profile**
3. Select **API Tokens** from the left sidebar
4. Click **Create Token**

### For Cloudflare Tunnel (recommended template):

5. Find **"Edit Cloudflare Tunnel"** template -> Click **Use template**

   Or for DNS management, use **"Edit zone DNS"** template

### For custom token with full control:

5. Click **Create Custom Token**
6. Configure:
   - **Token name:** `pve-tunnel-token` (or descriptive name)
   - **Permissions:**

| Scope   | Resource                    | Permission |
| ------- | --------------------------- | ---------- |
| Account | Cloudflare Tunnel           | Edit       |
| Account | Access: Apps and Policies   | Edit       |
| Zone    | DNS                         | Edit       |

   - **Zone Resources:** Include -> Specific zone -> `yourdomain.com`
   - **Account Resources:** Include -> Your account

7. Click **Continue to summary**
8. Click **Create Token**
9. **IMPORTANT:** Copy the token immediately - it's only shown once!

---

## 3. CF_DOMAIN

This is simply your domain name that you've added to Cloudflare:

```bash
export CF_DOMAIN="yourdomain.com"
```

---

## Complete Setup Example

```bash
# On your PVE host, add to ~/.bashrc or /etc/environment

export CF_API_TOKEN="v1.0-abc123xyz789..."      # From API Tokens page
export CF_ZONE_ID="1234567890abcdef12345678"    # From domain Overview sidebar
export CF_ACCOUNT_ID="abcdef1234567890abcdef"   # From domain Overview sidebar
export CF_DOMAIN="example.com"                   # Your domain name
```

Then reload:

```bash
source ~/.bashrc
```

---

## Verify Token Works

```bash
# Test API token
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json"

# Expected response: {"result":{"status":"active"},"success":true,...}
```

---

## References

- [Create API token - Cloudflare Docs](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
- [Find account and zone IDs - Cloudflare Docs](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/)
- [Account API tokens - Cloudflare Docs](https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/)
