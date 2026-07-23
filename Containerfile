# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder
RUN dnf5 upgrade -y 'kernel*' --refresh && \
    dnf5 -y install kernel-devel wget --refresh && \
    KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda --refresh && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio: Configuração do sistema e imagem final
FROM quay.io/fedora/fedora-bootc:44 AS final
LABEL ostree.bootable="true"
LABEL containers.bootc="1"

# 1. Ajuste do sistema de arquivos base e rebuild do Initramfs (Pouca variação)
RUN mkdir -vp /var/roothome /data /var/home && \
    dnf5 -y upgrade --refresh && \
    dnf5 -y install kernel-modules-extra wget --refresh && \
    printf 'omit_dracutmodules+=" nfs "\nomit_drivers+=" nfs nfsv3 nfsv4 nfs_acl nfs_common sunrpc rxrpc rpcrdma auth_rpcgss rpcsec_gss_krb5 "\n' | tee /etc/dracut.conf.d/no-nfs.conf && \
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dracut -f /usr/lib/modules/${kver}/initramfs.img ${kver} && \
    dnf5 clean all

# 2. Instalação dos módulos e drivers NVIDIA compilados (Camada pesada)
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm ./
RUN wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 download nvidia-kmod-common nvidia-driver-cuda && \
    rpm -vi --nodeps nvidia-kmod-common*.rpm && \
    rpm -vi --nodeps nvidia-driver-cuda*.rpm && \
    dnf5 -y install ./kmod-nvidia-*.rpm && \
    rm -rvf kmod-nvidia-*.rpm nvidia-kmod-common*.rpm nvidia-driver-cuda*.rpm && \
    dnf5 clean all

# 3. Pacotes base do ambiente gráfico GNOME Minimalista
RUN dnf5 install gnome-shell --setopt=install_weak_deps=False -y && \
    dnf5 clean all

# 4. Listas de pacotes personalizadas
# Copiadas separadamente para evitar a invalidação do cache do GNOME e NVIDIA
COPY pacotes_necessarios pacotes_desktop ./
RUN grep -v '^#' pacotes_necessarios | tr '\n' ' ' | xargs dnf5 install -y && \
    grep -v '^#' pacotes_desktop | tr '\n' ' ' | xargs dnf5 install -y && \
    rm -fv pacotes_necessarios pacotes_desktop && \
    dnf5 clean all

# 5. Configurações do sistema, scripts e links simbólicos (Arquivos com modificações frequentes)
# Mantidos por último para que edições nesses arquivos executem em instantes
COPY 10-nvidia-args.toml locale.conf post-install.sh post-install.service vconsole.conf zram-generator.conf ./
RUN rm -rvf /opt && mkdir -vp /var/opt && ln -vs /var/opt /opt && \
    mkdir -vp /var/usrlocal && mv -v /usr/local/* /var/usrlocal/ && \
    rm -rvf /usr/local && ln -vs /var/usrlocal /usr/local && \
    mv -v zram-generator.conf /etc/systemd/ && \
    mv -v vconsole.conf /etc/vconsole.conf && \
    mv -v locale.conf /etc/locale.conf && \
    mv -v 10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    mv -v post-install.sh /usr/bin/post-install.sh && \
    mv -v post-install.service /usr/lib/systemd/system/post-install.service && \
    chmod +x /usr/bin/post-install.sh && \
    systemctl enable post-install.service && \
    systemctl mask systemd-remount-fs.service && \
    systemctl mask akmods-keygen@akmods-keygen.service && \
    systemctl enable libvirtd.service && \
    systemctl enable spice-vdagentd.service && \
    rm -rfv /var/cache/* \
    /var/lib/* \
    /var/log/* \
    /var/tmp/* \
    /var/usrlocal/share/applications/mimeinfo.cache \
    /var/roothome/.*

# 6. Validação do bootc
RUN bootc container lint

# Terceiro estágio: Otimização e minimização de camadas OCI via Chunkah
FROM quay.io/coreos/chunkah AS chunkah
ARG CHUNKAH_CONFIG_STR
RUN --mount=from=final,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
    chunkah build --max-layers 128 \
    --label ostree.commit- \
    --label ostree.final-diffid- \
    --output oci:/run/src/out

FROM oci:out
LABEL ostree.bootable="true"
LABEL containers.bootc="1"
