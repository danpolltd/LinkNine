This folder contains files to publish on your update server.

Expected URLs (served from https://<DOWNLOADSERVER>/):

1) /qhtlfirewall/version.txt
   - Single line with the latest version, e.g. 0.1.6

2) /qhtlfirewall/changelog.txt
   - The release changelog (plain text)

3) /qhtlfirewall.tgz
   - Tar-gzipped package containing the top-level qhtlfirewall/ directory with install scripts.
   - The UI expects to run:
        wget https://<DOWNLOADSERVER>/qhtlfirewall.tgz
        tar -xzf qhtlfirewall.tgz
        cd qhtlfirewall
        sh install.sh

How to build qhtlfirewall.tgz from this repo:
- Run the helper script in this folder to produce update_artifacts/qhtlfirewall.tgz.
- Upload the three files to your update server in the paths listed above.
