eval `opam config env`
sudo apt update
opam depext -uiy mirage
cd ~
git clone https://github.com/mirage/mirage-skeleton.git
make -C mirage-skeleton && rm -rf mirage-skeleton
