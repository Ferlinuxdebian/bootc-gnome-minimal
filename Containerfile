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

FROM quay.io/coreos/chunkah AS chunkah

ARG CHUNKAH_CONFIG_STR

RUN --mount=from=final,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
    chunkah build > /run/src/out.ociarchive

FROM oci-archive:out.ociarchive
