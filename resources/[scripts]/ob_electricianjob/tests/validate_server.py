"""Executa o harness isolado com Lua 5.4; nao conecta ao FXServer."""
import sys
from pathlib import Path

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
from lupa.lua54 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().TEST_ROOT = Path(__file__).resolve().parent.parent.as_posix()
lua.execute("dofile(TEST_ROOT .. '/tests/server_spec.lua')")
