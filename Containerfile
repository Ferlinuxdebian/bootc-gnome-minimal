# Estágio de build do módulo da nvidia numa imagem separada
# Para evitar poluir a imagem final com os pacotes de desenvolvimento do kernel e ferramentas de construção
FROM quay.io/fedora/fedora-bootc:43 AS builder

RUN <<ELL
echo "Identifica a versão do kernel instalada no container, para instalar kernel-devel para Nvidia"
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

echo "Instala o kernel-devel necessário para nvidia módulo"
dnf5 -y install kernel-devel-"$KERNEL_VERSION"

echo "wget necessário para baixar repositórios"
dnf5 -y install wget

echo "Configura repositório negativo17 para drivers nvidia"
wget -O /etc/yum.repos.d/fedora-nvidia-580.repo \
https://negativo17.org/repos/fedora-nvidia-580.repo

echo "Instala o driver da nvidia"
dnf5 install -y nvidia-driver nvidia-driver-cuda --refresh

echo "Build nvidia kernel module para o kernel: $KERNEL_VERSION"
akmods --force --kernels "$KERNEL_VERSION"
ELL

# Imagem final do container
FROM quay.io/fedora/fedora-bootc:43

# Copia o módulo da nvidia construído no estágio anterior
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm ./

# Copia os arquivos necessários para o container
COPY 10-nvidia-args.toml locale.conf post-install.sh pacotes_rpm post-install.service vconsole.conf ./

# Bloco com a maior parte da configuração do sistema
RUN <<EOF
echo "Cria diretórios necessários"
mkdir -vp /var/roothome /data /var/home

echo "wget necessário para baixar repositórios"
dnf5 -y install wget

echo "Configura repositório negativo17 para libs da nvidia necessárias"
wget -O /etc/yum.repos.d/fedora-nvidia-580.repo \
https://negativo17.org/repos/fedora-nvidia-580.repo

echo "instalar o pacote do nvidia-kmod-common e nvidia-driver-cuda necessários, mas sem toda as dependências para construção do módulo"
dnf5 download nvidia-kmod-common nvidia-driver-cuda
rpm -vi --nodeps nvidia-kmod-common*.rpm
rpm -vi --nodeps nvidia-driver-cuda*.rpm

echo "instalar o kmod-nvidia previamente construído na imagem anterior"
dnf5 -y install ./kmod-nvidia-*.rpm

echo "Para /opt gravavel"
rm -rvf /opt && mkdir -vp /var/opt && ln -vs /var/opt /opt

echo "Para /usr/local gravavel"
mkdir -vp /var/usrlocal && mv -v /usr/local/* /var/usrlocal/ 2>/dev/null
rm -rvf /usr/local && ln -vs /var/usrlocal /usr/local

echo "Configura o TTY para o layout de teclado BR, bem como o sistema de locale PT-BR"
mv -v vconsole.conf /etc/vconsole.conf
mv -v locale.conf /etc/locale.conf

echo "Configura os argumento do kernel para nvidia"
echo "veja a doc https://bit.ly/4qA7J73"
mv -v 10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml

echo "Move o script de pós instalação"
mv -v post-install.sh /usr/bin/post-install.sh

echo "Move o serviço de pós instalação"
echo "Prefira /usr sempre que possível a etc veja: https://bit.ly/4tBoFx4"
mv -v post-install.service /usr/lib/systemd/system/post-install.service

echo "Instala os flatpaks no primeiro boot"
chmod +x /usr/bin/post-install.sh
systemctl enable post-install.service

echo "Atualiza todo o container para os pacotes mais recentes, mas não mexe no kernel nem no bootloader"
echo "Veja a doc https://bit.ly/4aPjNvJ"
dnf5 -y upgrade --refresh -x 'kernel*' -x 'grub2*' -x 'dracut*' -x 'shim*' -x 'fwupd*'

echo "Identifica a versão do kernel instalada no container, para instalar kernel-modules-extra"
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

echo "Instala o kernel-modules-extra para um melhor suporte a hardware"
dnf5 -y install kernel-modules-extra-"$KERNEL_VERSION" 

echo "Limpeza de residuos desse bloco de construção, para reduzir o tamanho da imagem final"
rm -rvf kmod-nvidia-*.rpm nvidia-kmod-common*.rpm nvidia-driver-cuda*.rpm
dnf5 clean all
EOF

# Bloco para instalar o gnome shell minimal, e fazer uma última limpeza
RUN echo "Install gnome shell minimal" && \
dnf5 install gnome-shell --setopt=install_weak_deps=False -y && \
dnf5 clean all

# Bloco para instalar os pacotes rpm listados no arquivo pacotes_rpm
# E também desativa alguns serviços desnecessários e habilita outros, além de fazer uma limpeza final
RUN <<EOR
echo "instala os pacotes rpm listados no arquivo pacotes_rpm"
tr '\n' ' ' < pacotes_rpm | xargs dnf5 install -y

echo "Desativa alguns serviços desnecessários e habilita outros"
systemctl mask systemd-remount-fs.service
systemctl mask akmods-keygen@akmods-keygen.service
systemctl enable zram-swap.service
systemctl enable libvirtd.service
systemctl enable spice-vdagentd.service

echo "Limpeza de resíduos de construção" 
rm -rvf pacotes_rpm 
dnf5 clean all
EOR

# Verificar por erros na imagem 
RUN bootc container lint
