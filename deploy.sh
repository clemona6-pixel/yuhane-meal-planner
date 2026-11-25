#!/usr/bin/env bash
# 유하네 식단 — GitHub Pages 배포
# 사용법: bash work/yuhane-meal-planner/deploy.sh
set -uo pipefail

OWNER="${OWNER:-clemona6-pixel}"
REPO="${REPO:-yuhane-meal-planner}"
URL="https://${OWNER}.github.io/${REPO}/"
cd "$(dirname "$0")"

SRC="../../downloads/meal-planner.html"
echo "0) 빌드 결과 반영"
if [ -f "$SRC" ]; then
  if cmp -s "$SRC" index.html; then
    echo "   index.html 이미 최신"
  else
    cp "$SRC" index.html && echo "   downloads/meal-planner.html → index.html ($(wc -c < index.html) bytes)"
  fi
else
  echo "   $SRC 없음 → python3 meal-planner/build.py 를 먼저 실행해 주세요." >&2
  exit 2
fi

echo "1) 저장소 확인"
if ! gh api "repos/${OWNER}/${REPO}" --jq '.full_name + " private=" + (.private|tostring)' 2>/dev/null; then
  echo "   저장소 없음 → github.com/new 에서 ${REPO} (Public) 를 먼저 만들어 주세요."
  exit 2
fi

echo "2) 원격 커밋 상태"
COMMITS=$(gh api "repos/${OWNER}/${REPO}/commits?per_page=5" --jq 'length' 2>/dev/null)
case "$COMMITS" in ''|*[!0-9]*) COMMITS=0 ;; esac   # 409 Git Repository is empty → 0
echo "   원격 커밋 수: ${COMMITS}"

git remote remove origin 2>/dev/null
git remote add origin "https://github.com/${OWNER}/${REPO}.git"

echo "3) 푸시"
if [ "$COMMITS" = "0" ]; then
  git push -u origin main || { echo "   푸시 실패"; exit 3; }
elif [ "$COMMITS" = "1" ]; then
  # 저장소 만들 때 생긴 README 한 개뿐 → 우리 내용으로 대체
  git push -u origin main --force || { echo "   강제 푸시 실패"; exit 3; }
else
  # 이미 여러 번 배포된 저장소 → 새 커밋만 이어서 올림(덮어쓰지 않음)
  git push -u origin main || { echo "   푸시 실패(원격과 갈라졌는지 확인해 주세요)"; exit 3; }
fi

echo "4) Pages 활성화"
if gh api -X POST "repos/${OWNER}/${REPO}/pages" -f 'source[branch]=main' -f 'source[path]=/' >/dev/null 2>&1; then
  echo "   API로 활성화됨"
else
  echo "   API 권한 없음(pages). 아래에서 직접 켜 주세요:"
  echo "   https://github.com/${OWNER}/${REPO}/settings/pages  → Source: Deploy from a branch / main / (root) → Save"
fi

echo "5) 배포 대기 (최대 5분)"
for i in $(seq 1 30); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$URL")
  echo "   [${i}/30] ${URL} → ${CODE}"
  [ "$CODE" = "200" ] && break
  sleep 10
done

echo "6) 내용 확인"
curl -s "$URL" | grep -o '<title>[^<]*</title>' | head -1
curl -s "$URL" | grep -c 'MEAL_PLAN_DATA' | sed 's/^/   MEAL_PLAN_DATA hits: /'
