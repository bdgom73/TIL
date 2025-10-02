@echo off
REM 오늘 날짜를 YYYY-MM-DD 형식으로 가져오기
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%i

REM 파일 경로
set FILE=_posts\%TODAY%-today-i-learned.md

REM _posts 폴더 없으면 생성
if not exist _posts (
    mkdir _posts
)

REM 파일 생성
echo --- > %FILE%
echo title: Today I Learned >> %FILE%
echo date: %TODAY% >> %FILE%
echo --- >> %FILE%

echo 파일 생성 완료: %FILE%
pause
