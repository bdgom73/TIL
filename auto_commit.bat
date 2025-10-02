@echo off
setlocal enabledelayedexpansion

REM 오늘 날짜를 YYYY-MM-DD 형식으로 가져오기
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%i

REM 자동 커밋 메시지 (한글)
set MSG=%TODAY% TIL

REM Git 명령어 실행
git add -A
git commit -m "%MSG%"
git push

echo ================================
echo Git 자동 커밋 및 푸시 완료!
echo 메시지: %MSG%
echo ================================

pause
