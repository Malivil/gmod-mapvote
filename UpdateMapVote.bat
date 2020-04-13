@echo off
set /p changes="Enter Changes: "
"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\bin\gmpublish.exe"  update -addon "gmod-mapvote.gma" -id "1472570320" -changes "%changes%"
pause