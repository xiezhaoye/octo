from pathlib import Path
import subprocess

root=Path(__file__).resolve().parent
source=root/'Sources/DualPane/Resources/OctoDock.png'
iconset=root/'.build/Octo.iconset'
iconset.mkdir(parents=True,exist_ok=True)
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        target=iconset/f'icon_{size}x{size}{"@2x" if scale==2 else ""}.png'
        subprocess.run(['sips','-z',str(size*scale),str(size*scale),str(source),'--out',str(target)],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(root/'Assets/AppIcon.icns')],check=True)
print('已从提供的 Logo 生成 macOS 应用图标。')
