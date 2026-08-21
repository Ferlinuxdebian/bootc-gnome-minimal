# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder
RUN KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio: Configuração do sistema e imagem final
FROM quay.io/fedora/fedora-bootc:44

# 1. Configuração de repositórios e driver NVIDIA
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm /tmp/nvidia/
RUN kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install --setopt=tsflags=nodocs "kernel-modules-extra-${kver}" && \
    dnf5 download --destdir=/tmp/nvidia nvidia-kmod-common nvidia-driver-cuda && \
    dnf5 -y install --setopt=tsflags=nodocs /tmp/nvidia/nvidia-kmod-common*.rpm /tmp/nvidia/nvidia-driver-cuda*.rpm /tmp/nvidia/kmod-nvidia-*.rpm && \
    rm -rf /tmp/nvidia /var/cache/dnf /var/cache/libdnf5

# 2. Instalação UNIFICADA do GNOME, pacotes essenciais e pacotes desktop
COPY pacotes_necessarios pacotes_desktop /tmp/
RUN PACKAGES_NECESSARIOS=$(grep -v '^#' /tmp/pacotes_necessarios | tr '\n' ' ') && \
    PACKAGES_DESKTOP=$(grep -v '^#' /tmp/pacotes_desktop | tr '\n' ' ') && \
    dnf5 install --setopt=tsflags=nodocs -y \
        gnome-shell \
        libjpeg-turbo \
        wayland-libs \
        gawk \
        python3-argcomplete \
        ${PACKAGES_NECESSARIOS} \
        ${PACKAGES_DESKTOP} && \
    dnf5 clean all && \
    rm -rf /var/cache/dnf /var/cache/libdnf5 /var/log/* /tmp/* /var/tmp/* /tmp/pacotes_*

# 3. Configurações, scripts, links do sistema e tratamento de /opt e /usr/local
COPY 10-nvidia-args.toml locale.conf post-install.sh post-install.service vconsole.conf zram-generator.conf libvirt.conf nvidia-power.conf /tmp/sysconfig/
RUN mkdir -vp /var/opt /var/usrlocal /etc/sysusers.d /usr/lib/bootc/kargs.d /etc/modprobe.d && \
    rm -rfv /opt /usr/local && \
    ln -vs /var/opt /opt && \
    ln -vs /var/usrlocal /usr/local && \
    mv /tmp/sysconfig/libvirt.conf /etc/sysusers.d/ && \
    mv /tmp/sysconfig/zram-generator.conf /usr/lib/systemd/zram-generator.conf.d/override.conf 2>/dev/null || mv /tmp/sysconfig/zram-generator.conf /etc/systemd/ && \
    mv /tmp/sysconfig/nvidia-power.conf /etc/modprobe.d/ && \
    mv /tmp/sysconfig/vconsole.conf /etc/vconsole.conf && \
    mv /tmp/sysconfig/locale.conf /etc/locale.conf && \
    mv /tmp/sysconfig/10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    mv /tmp/sysconfig/post-install.sh /usr/bin/post-install.sh && \
    mv /tmp/sysconfig/post-install.service /usr/lib/systemd/system/post-install.service && \
    chmod +x /usr/bin/post-install.sh && \
    systemctl enable post-install.service libvirtd.service spice-vdagentd.service && \
    systemctl mask systemd-remount-fs.service akmods-keygen@akmods-keygen.service && \
    rm -rf /tmp/sysconfig /var/cache/dnf /var/cache/libdnf5 /var/log/* /tmp/* /var/tmp/*

# 4. Validação do bootc
RUN bootc container lint
