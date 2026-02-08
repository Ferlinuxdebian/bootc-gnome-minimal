FROM quay.io/fedora/fedora-bootc:43

# Cria os diretórios necessários
RUN mkdir -p /var/roothome /data /var/home

# Copia os arquivos necessários para o container
COPY 10-nvidia-args.toml locale.conf post-install.sh pacotes_rpm post-install.service vconsole.conf ./

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

echo "Atualiza todo o container para os pacotes mais recentes, mas não mexe no kernel nem no bootloader"
dnf5 -y upgrade --refresh -x 'kernel*' -x 'grub2*' -x 'dracut*' -x 'shim*' -x 'fwupd*'

echo "Identifica a versão do kernel instalada no container, para instalar o kerne-modules-extra e kernel-devel para Nvidia"
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

echo "Instala o kernel-modules-extra para um melhor suporte a hardware e kernel-devel para Nvidia"
dnf5 -y install kernel-modules-extra-"$KERNEL_VERSION" kernel-devel-"$KERNEL_VERSION"

echo "wget necessário para baixar repositórios"
dnf5 -y install wget

echo "Configura repositório negativo17 para drivers nvidia"
wget -O /etc/yum.repos.d/fedora-nvidia-580.repo \
https://negativo17.org/repos/fedora-nvidia-580.repo

echo "Install nvidia driver and akmoda"
dnf5 install -y nvidia-driver nvidia-driver-cuda --refresh

echo "Build nvidia kernel module para o kernel: $KERNEL_VERSION"
akmods --force --kernels "$KERNEL_VERSION"

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

echo "Limpeza de resíduos de contrução" 
dnf5 clean all
rm -rf /var/log/dnf5.log* /var/log/akmods/*
rm -rf /var/cache/*
rm -rf /var/lib/dnf/repos/*
EOF

# Verificar por erros na imagem 
RUN bootc container lint
