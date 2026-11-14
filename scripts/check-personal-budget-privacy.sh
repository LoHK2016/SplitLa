#!/bin/sh
# Checks that the Personal Budget cannot reach the server.
#
# The Personal Budget lives only on the device. This is a check of the source,
# not a recording of network traffic: it fails if any code that talks to the
# server could see the budget, or if the database has anywhere to put one.
#
#   1. No file that talks to the server (anything under App/SplitLa/Sync, or
#      any file that imports Supabase) mentions the Personal Budget.
#   2. Only the files listed below may touch the Personal Budget store, so a
#      new use has to be added here on purpose.
#   3. The database migrations have no table, column or function for it.
#   4. None of the files allowed to touch the Personal Budget write logs, so the
#      value cannot end up in one. (The app has no analytics at all.)
set -eu
cd "$(dirname "$0")/.."
app=App/SplitLa
failed=0

server_files=$( { find "$app/Sync" -name '*.swift'; grep -rl '^import Supabase' "$app" --include='*.swift'; } | sort -u)
for file in $server_files; do
  if grep -n -i 'personal *budget\|budgetStore' "$file"; then
    echo "FAIL: $file talks to the server and mentions the Personal Budget" >&2
    failed=1
  fi
done

allowed="$app/Budget/PersonalBudgetStore.swift $app/Budget/PersonalBudgetView.swift $app/Activities/ActivityView.swift $app/SplitLaApp.swift"
for file in $(grep -rl 'PersonalBudgetStore\|PersonalBudgetRecord' "$app" --include='*.swift'); do
  case " $allowed " in
    *" $file "*) ;;
    *) echo "FAIL: $file uses the Personal Budget store but is not on the allowed list" >&2; failed=1 ;;
  esac
done

for file in $allowed; do
  if grep -n -E '\b(print|debugPrint|dump|NSLog|os_log)\(|Logger\(' "$file"; then
    echo "FAIL: $file can see the Personal Budget and writes logs" >&2
    failed=1
  fi
done

if grep -rn -i 'personal' supabase/migrations; then
  echo "FAIL: the database mentions something personal; the Personal Budget must stay on the device" >&2
  failed=1
fi

[ "$failed" -eq 0 ] && echo "OK: the Personal Budget stays on the device"
exit "$failed"
