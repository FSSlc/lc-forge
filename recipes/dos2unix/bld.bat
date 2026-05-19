@rem Build script for dos2unix on conda-forge/windows

@rem 1. Python one-liner for in-file replacement of hard-coded install path in vc.mak
python -c "from pathlib import Path; from os import getenv; p=Path('vc.mak'); p.write_text(p.read_text(encoding='utf-8').replace('c:\\usr\\local',getenv('PREFIX')), encoding='utf-8')"

@rem 2. nmake using vc.mak
nmake /f vc.mak all

@rem 3 nmake install to $PREFIX
nmake /f vc.mak install
