copy "%LUA_SOURCEPATH%\xpl*.lua" src\
del src\xplhal.lua
xcopy "%LUA_SOURCEPATH%\xpl\*.*" src\xpl\ /Y/E
"%LUA_SOURCEPATH%\luadoc_start.lua" -d doc src > luadoc_output.txt
type luadoc_output.txt
start doc\index.html
pause



