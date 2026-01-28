FROM quay.io/fedora/fedora-bootc:43

# Cria os diretórios necessários
RUN mkdir -p /var/roothome /data /var/home

# Copia os arquivos necessários para o container
COPY 10-nvidia-args.toml locale.conf post-install.sh pacotes_rpm fake_uname-r post-install.service vconsole.conf ./

RUN <<EOF
echo "Para /opt gravavel"
rm -rf /opt && mkdir -p /var/opt && ln -s /var/opt /opt

echo "Para /usr/local gravavel"
mkdir -p /var/usrlocal && mv /usr/local/* /var/usrlocal/ 2>/dev/null
rm -rf /usr/local && ln -s /var/usrlocal /usr/local

echo "Configura o TTY para o layout de teclado BR, bem como o sistema de locale PT-BR"
mv vconsole.conf /etc/vconsole.conf
mv locale.conf /etc/locale.conf

echo "Configura os argumento do kernel nvidia"
mv 10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml

echo "Move o script de pós instalação"
mv post-install.sh /usr/bin/post-install.sh

echo "Move o serviço de pós instalação"
mv post-install.service /etc/systemd/system/post-install.service

echo "wget necessário para baixar repositórios"
dnf5 -y install wget

echo "Configura repositório negativo17 para drivers nvidia"
wget -O /etc/yum.repos.d/fedora-nvidia-580.repo \
https://negativo17.org/repos/fedora-nvidia-580.repo

echo "Engana o uname -r no container para compilar o driver da nvidia"
mv fake_uname-r /usr/bin/fake_uname-r
chmod +x /usr/bin/fake_uname-r
/usr/bin/fake_uname-r

echo "Install nvidia driver and akmoda"
dnf5 install -y nvidia-driver nvidia-driver-cuda kernel-devel --refresh

echo "Build nvidia kernel module"
akmods --force --rebuild
dracut --force

echo "Install gnome shell minimal"
dnf5 install gnome-shell --setopt=install_weak_deps=False -y

echo "instala os pacotes rpm listados no arquivo pacotes_rpm"
tr '\n' ' ' < pacotes_rpm | xargs dnf5 install -y

echo "Instala os flatpaks no primeiro boot"
chmod +x /usr/bin/post-install.sh
systemctl enable post-install.service

echo "Desativa alguns serviços desnecessários e habilita outros"
systemctl mask systemd-remount-fs.service
systemctl mask akmods-keygen@akmods-keygen.service
systemctl enable zram-swap.service
systemctl enable libvirtd.service
systemctl enable spice-vdagentd.service
EOF