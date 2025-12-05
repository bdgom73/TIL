@echo off
REM 1. 날짜 정보 가져오기 (PowerShell 사용)
REM 연도(YYYY), 월(MM), 전체날짜(YYYY-MM-DD)를 각각 변수에 저장
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy"') do set YEAR=%%i
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format MM"') do set MONTH=%%i
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%i

REM 2. 경로 및 파일명 설정
REM 목표 폴더 경로: 2025\12 (윈도우는 역슬래시 \ 사용)
set BASE_DIR=%YEAR%\%MONTH%
REM 파일명: 2025-12-06-today-i-learned.md
set FILENAME=%TODAY%-today-i-learned.md
REM 전체 파일 경로 조합
set FILE=%BASE_DIR%\%FILENAME%

REM 3. 폴더 생성
REM 해당 연/월 폴더가 없으면 생성 (하위 폴더까지 한 번에 생성됨)
if not exist "%BASE_DIR%" (
    mkdir "%BASE_DIR%"
)

REM 4. 파일 생성 및 내용 작성
echo --- > "%FILE%"
echo title: Today I Learned >> "%FILE%"
echo date: %TODAY% >> "%FILE%"
echo --- >> "%FILE%"

echo 파일 생성 완료: %FILE%
pause