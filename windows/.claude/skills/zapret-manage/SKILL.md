# Skill: zapret-manage

Manage domain lists and the winws2 service.

## Domain List Location
`C:\zapret\zapret-winws\files\user-hostlist.txt`

One domain per line, no `http://`, no trailing slashes:
```
youtube.com
discord.com
telegram.org
```

## Scenarios

### Check service status
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-service.ps1 -Action status
```

### Start / Stop / Restart service
Show the command, explain, confirm, then run:
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-service.ps1 -Action start
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-service.ps1 -Action stop
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-service.ps1 -Action restart
```

### Add domains
User says "добавь discord.com и twitch.tv":
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-hostlist.ps1 -Action add -Domains "discord.com,twitch.tv"
```
After adding → restart service for changes to take effect.

### Remove domains
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-hostlist.ps1 -Action remove -Domains "twitch.tv"
```

### List current domains
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-hostlist.ps1 -Action list
```

### Merge seed list
Merges `data\seed-list.txt` (popular sites) into user-hostlist.txt:
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-manage\scripts\manage-hostlist.ps1 -Action merge-seed -SeedPath "data\seed-list.txt"
```

## After any domain list change
Restart service for changes to apply:
```powershell
sc stop winws2
sc start winws2
```
Tell user: "Список обновлён. Служба перезапущена — изменения применены."

## User confirmation required for
- Removing domains (irreversible without backup)
- Stopping the service (breaks bypass until started again)
- `merge-seed` (adds many domains)

## Auto-manage vs manual list
zapret2 can run in **autohostlist** mode (bypass all traffic) or **hostlist** mode (only listed domains).
- autohostlist mode: no domain management needed — everything goes through zapret
- hostlist mode: only `user-hostlist.txt` domains are bypassed

Current mode depends on config in `zapret.conf`. If user asks to "bypass everything" → suggest switching to autohostlist mode (update config via zapret-config).
