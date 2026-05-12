```Dockerfile
# Estágio de build do módulo da NVIDIA
# Separado para evitar poluir a imagem final com ferramentas de compilação
FROM quay.io/fedora/fedora-bootc:44 AS builder

RUN set -e && \
    \
    # Atualiza o kernel da imagem
    dnf5 upgrade -y 'kernel*' --refresh && \
    \
    # Instala o kernel-devel necessário para o módulo NVIDIA
    dnf5 install -y kernel-devel --refresh && \
    \
    # Instala wget para baixar repositórios
    dnf5 install -y wget && \
    \
    # Configura o repositório negativo17
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo \
    https://negativo17.org/repos/fedora-nvidia-580.repo && \
    \
    # Instala o driver NVIDIA
    dnf5 install -y nvidia-driver nvidia-driver-cuda --refresh && \
    \
    # Identifica a versão do kernel instalada
    KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    \
    # Compila o módulo NVIDIA para o kernel instalado
    akmods --force --kernels "$KERNEL_VERSION"

# Imagem final
FROM quay.io/fedora/fedora-bootc:44 AS final

# Copia o módulo previamente compilado
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm ./

# Copia arquivos necessários
COPY 10-nvidia-args.toml \
     locale.conf \
     post-install.sh \
     pacotes_desktop \
     pacotes_necessarios \
     post-install.service \
     vconsole.conf \
     zram-generator.conf \
     ./

RUN set -e && \
    \
    # Cria diretórios necessários
    mkdir -vp /var/roothome /data /var/home && \
    \
    # Atualiza os pacotes da imagem
    dnf5 upgrade -y --refresh && \
    \
    # Instala módulos extras do kernel
    dnf5 install -y kernel-modules-extra --refresh && \
    \
    # Remove módulos NFS desnecessários do initramfs
    printf '%s\n' \
    'omit_dracutmodules+=" nfs "' \
    'omit_drivers+=" nfs nfsv3 nfsv4 nfs_acl nfs_common sunrpc rxrpc rpcrdma auth_rpcgss rpcsec_gss_krb5 "' \
    > /etc/dracut.conf.d/no-nfs.conf && \
    \
    # Regenera o initramfs
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dracut -f /usr/lib/modules/${kver}/initramfs.img ${kver} && \
    \
    # Instala wget
    dnf5 install -y wget && \
    \
    # Configura zram
    mv -v zram-generator.conf /etc/systemd/ && \
    \
    # Configura repositório NVIDIA
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo \
    https://negativo17.org/repos/fedora-nvidia-580.repo && \
    \
    # Baixa pacotes necessários sem dependências de build
    dnf5 download nvidia-kmod-common nvidia-driver-cuda && \
    rpm -vi --nodeps nvidia-kmod-common*.rpm && \
    rpm -vi --nodeps nvidia-driver-cuda*.rpm && \
    \
    # Instala módulo NVIDIA compilado
    dnf5 install -y ./kmod-nvidia-*.rpm && \
    \
    # Torna /opt gravável
    rm -rvf /opt && \
    mkdir -vp /var/opt && \
    ln -vs /var/opt /opt && \
    \
    # Torna /usr/local gravável
    mkdir -vp /var/usrlocal && \
    mv -v /usr/local/* /var/usrlocal/ 2>/dev/null || true && \
    rm -rvf /usr/local && \
    ln -vs /var/usrlocal /usr/local && \
    \
    # Configura locale e teclado
    mv -v vconsole.conf /etc/vconsole.conf && \
    mv -v locale.conf /etc/locale.conf && \
    \
    # Configura argumentos do kernel NVIDIA
    mv -v 10-nvidia-args.toml \
    /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    \
    # Instala script de pós-instalação
    mv -v post-install.sh /usr/bin/post-install.sh && \
    chmod +x /usr/bin/post-install.sh && \
    \
    # Instala serviço de pós-instalação
    mv -v post-install.service \
    /usr/lib/systemd/system/post-install.service && \
    \
    # Habilita serviço
    systemctl enable post-install.service && \
    \
    # Limpeza
    rm -rvf kmod-nvidia-*.rpm \
             nvidia-kmod-common*.rpm \
             nvidia-driver-cuda*.rpm && \
    \
    dnf5 clean all && \
    \
    rm -rfv /var/cache/* \
             /var/lib/* \
             /var/log/* \
             /var/tmp/*

# Instala GNOME Shell minimal
RUN dnf5 install gnome-shell \
        --setopt=install_weak_deps=False \
        -y && \
    \
    dnf5 clean all && \
    \
    rm -rfv /var/cache/* \
             /var/lib/* \
             /var/log/* \
             /var/tmp/*

# Instala pacotes adicionais e configura serviços
RUN set -e && \
    \
    # Instala pacotes necessários
    grep -v '^#' pacotes_necessarios | \
    tr '\n' ' ' | \
    xargs dnf5 install -y && \
    \
    # Instala pacotes do ambiente gráfico
    grep -v '^#' pacotes_desktop | \
    tr '\n' ' ' | \
    xargs dnf5 install -y && \
    \
    # Configuração de serviços
    systemctl mask systemd-remount-fs.service && \
    systemctl mask akmods-keygen@akmods-keygen.service && \
    systemctl enable libvirtd.service && \
    systemctl enable spice-vdagentd.service && \
    \
    # Limpeza final
    rm -rvf pacotes_rpm && \
    \
    dnf5 clean all && \
    \
    rm -rfv /var/cache/* \
             /var/lib/* \
             /var/log/* \
             /var/tmp/* \
             /var/usrlocal/share/applications/mimeinfo.cache \
             /var/roothome/.*

# Verifica erros da imagem
RUN bootc container lint

ARG CHUNKAH_CONFIG_STR
# Estágio de build do módulo da nvidia numa imagem separada
# Para evitar poluir a imagem final com os pacotes de desenvolvimento do kernel e ferramentas de construção
FROM quay.io/fedora/fedora-bootc:44 AS builder

RUN <<ELL
set -e

echo "Atualiza o kernel da imagem" 
dnf5 upgrade -y 'kernel*' --refresh 

echo "Instala o kernel-devel necessário para nvidia módulo"
dnf5 -y install kernel-devel --refresh

echo "Identifica a versão do kernel instalada no container, para instalar kernel-devel para Nvidia"
KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

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
FROM quay.io/fedora/fedora-bootc:44 AS final

# Copia o módulo da nvidia construído no estágio anterior
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm ./

# Copia os arquivos necessários para o container
COPY 10-nvidia-args.toml locale.conf post-install.sh pacotes_desktop pacotes_necessarios post-install.service vconsole.conf zram-generator.conf ./

# Bloco com a maior parte da configuração do sistema
RUN <<EOF
set -e

echo "Cria diretórios necessários"
mkdir -vp /var/roothome /data /var/home

echo "Atualiza todo o container para os pacotes mais recentes"
dnf5 -y upgrade --refresh 

echo "Instala o kernel-modules-extra para um melhor suporte a hardware"
dnf5 -y install kernel-modules-extra --refresh

echo "Remove modulo do nfs desnecessário no initramfs"
tee /etc/dracut.conf.d/no-nfs.conf >/dev/null << 'NONFS'
omit_dracutmodules+=" nfs "
omit_drivers+=" nfs nfsv3 nfsv4 nfs_acl nfs_common sunrpc rxrpc rpcrdma auth_rpcgss rpcsec_gss_krb5 "
NONFS

echo "Gera um novo initramfs no local correto"
kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
dracut -f /usr/lib/modules/${kver}/initramfs.img ${kver}

echo "wget necessário para baixar repositórios"
dnf5 -y install wget

echo "Configura o zram"
mv -v zram-generator.conf /etc/systemd/

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

echo "Limpeza de residuos desse bloco de construção, para reduzir o tamanho da imagem final"
rm -rvf kmod-nvidia-*.rpm nvidia-kmod-common*.rpm nvidia-driver-cuda*.rpm
dnf5 clean all
rm -rfv /var/cache/* \
        /var/lib/* \
        /var/log/* \
        /var/tmp/* 
EOF

# Bloco para instalar o gnome shell minimal, e fazer uma última limpeza
RUN echo "Install gnome shell minimal" && \
dnf5 install gnome-shell --setopt=install_weak_deps=False -y && \
dnf5 clean all && \
rm -rfv /var/cache/* \
       /var/lib/* \
       /var/log/* \
       /var/tmp/* 

# Bloco para instalar os pacotes rpm listados no arquivo pacotes_rpm
# E também desativa alguns serviços desnecessários e habilita outros, além de fazer uma limpeza final
RUN <<EOR
set -e

echo "instala os pacotes rpm necessários"
grep -v '^#' pacotes_necessarios | tr '\n' ' ' | xargs dnf5 install -y

echo "Instala pacotes especificos de Desktop Environment"
grep -v '^#' pacotes_desktop | tr '\n' ' ' | xargs dnf5 install -y

echo "Desativa alguns serviços desnecessários e habilita outros"
systemctl mask systemd-remount-fs.service
systemctl mask akmods-keygen@akmods-keygen.service
systemctl enable libvirtd.service
systemctl enable spice-vdagentd.service

echo "Limpeza de resíduos de construção" 
rm -rvf pacotes_rpm 
dnf5 clean all
rm -rfv /var/cache/* \
        /var/lib/* \
        /var/log/* \
        /var/tmp/* \
        /var/usrlocal/share/applications/mimeinfo.cache \
        /var/roothome/.*
        
EOR

# Verificar por erros na imagem 
RUN bootc container lint

# Chunkah para aproveitar layers não alterdas
ARG CHUNKAH_CONFIG_STR

FROM quay.io/coreos/chunkah AS chunkah
ARG CHUNKAH_CONFIG_STR
RUN --mount=from=final,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        chunkah build --prune /sysroot/ --max-layers 128 \
          --label ostree.commit- --label ostree.final-diffid- \
          > /run/src/out.ociarchive

FROM oci-archive:out.ociarchive
