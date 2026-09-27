# build-minecraft-disc-pack.sh

Shell-Script, das Minecraft-Jukebox-CDs durch eigene Musik ersetzt und ein Resource-Pack baut.

## Bedarf

bash 4+, ffmpeg, zip, unzip

```bash
sudo apt install ffmpeg zip unzip
```

## Start

Script und Musik in denselben Ordner legen:

```bash
chmod +x build-minecraft-disc-pack.sh
bash build-minecraft-disc-pack.sh
```

Menü: CDs wählen, MP3s aus dem Script-Ordner zuordnen, einmal bauen. Ein bestehendes Pack kann geöffnet und um weitere CDs ergänzt werden.

## Server

```properties
resource-pack=https://DEINE-URL/custom-discs.zip
resource-pack-sha1=WERT_AUS_DEM_SCRIPT
require-resource-pack=true
```

Nur Musik verwenden, an der du die Rechte hast.
