@echo off
chcp 65001 >nul
echo Starting PixelBomb Backend Server...
cd server
go run .
pause
