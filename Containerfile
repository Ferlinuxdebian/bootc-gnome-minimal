# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder

RUN KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y --nodocs install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y --nodocs nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"


# Segundo estágio: Configuração do sistema e imagem final
FROM quay.io/fedora/fedora-bootc:44 AS final

# 1. Ajuste do sistema de arquivos base e rebuild do Initramfs
RUN mkdir -vp /var/roothome /data /var/home && \
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y --nodocs install "kernel-modules-extra-${kver}" && \
    printf 'omit_dracutmodules+=" nfs "\nomit_drivers+=" nfs nfsv3 nfsv4 nfs_acl nfs_common sunrpc rxrpc rpcrdma auth_rpcgss rpcsec_gss_krb5 "\n' | tee /etc/dracut.conf.d/no-nfs.conf && \
    dracut -f --reproducible "/usr/lib/modules/${kver}/initramfs.img" "${kver}" && \
    dnf5 clean all && \
    rm -rf /var/cache/* /var/log/* /tmp/* /var/tmp/*

# 2. Instalação dos módulos e drivers NVIDIA compilados
# Copiamos o repositório do builder para evitar uso do wget na imagem final
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/fedora-nvidia-580.repo
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm /tmp/nvidia-modules/

RUN dnf5 -y --nodocs install \
    nvidia-kmod-common \
    nvidia-driver-cuda \
    /tmp/nvidia-modules/kmod-nvidia-*.rpm && \
    rm -rf /tmp/nvidia-modules && \
    dnf5 clean all && \
    rm -rf /var/cache/* /var/log/* /tmp/* /var/tmp/*

# 3. Pacotes base do ambiente gráfico GNOME Minimalista
RUN dnf5 install -y --nodocs --setopt=install_weak_deps=False gnome-shell && \
    dnf5 clean all && \
    rm -rf /var/cache/* /var/log/* /tmp/* /var/tmp/*

# 4. Listas de pacotes personalizadas
COPY pacotes_necessarios pacotes_desktop /tmp/
RUN dnf5 install -y --nodocs \
    $(grep -v '^#' /tmp/pacotes_necessarios) \
    $(grep -v '^#' /tmp/pacotes_desktop) && \
    rm -f /tmp/pacotes_necessarios /tmp/pacotes_desktop && \
    dnf5 clean all && \
    rm -rf /var/cache/* /var/log/* /tmp/* /var/tmp/*

# 5. Configurações do sistema, scripts e links simbólicos
COPY 10-nvidia-args.toml locale.conf post-install.sh post-install.service vconsole.conf zram-generator.conf /tmp/sysconfig/

RUN rm -rf /opt && mkdir -vp /var/opt && ln -vs /var/opt /opt && \
    mkdir -vp /var/usrlocal && mv -v /usr/local/* /var/usrlocal/ 2>/dev/null || true && \
    rm -rf /usr/local && ln -vs /var/usrlocal /usr/local && \
    mv -v /tmp/sysconfig/zram-generator.conf /usr/lib/systemd/ && \
    mv -v /tmp/sysconfig/vconsole.conf /etc/vconsole.conf && \
    mv -v /tmp/sysconfig/locale.conf /etc/locale.conf && \
    mkdir -p /usr/lib/bootc/kargs.d && \
    mv -v /tmp/sysconfig/10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    mv -v /tmp/sysconfig/post-install.sh /usr/bin/post-install.sh && \
    mv -v /tmp/sysconfig/post-install.service /usr/lib/systemd/system/post-install.service && \
    chmod +x /usr/bin/post-install.sh && \
    systemctl enable post-install.service && \
    systemctl mask systemd-remount-fs.service && \
    systemctl mask akmods-keygen@akmods-keygen.service && \
    systemctl enable libvirtd.service && \
    systemctl enable spice-vdagentd.service && \
    rm -rf /tmp/sysconfig && \
    rm -rf /var/cache/* \
           /var/lib/dnf/* \
           /var/log/* \
           /var/tmp/* \
           /tmp/* \
           /var/usrlocal/share/applications/mimeinfo.cache \
           /var/roothome/.* 2>/dev/null || true

# 6. Validação do bootc
RUN bootc container lint