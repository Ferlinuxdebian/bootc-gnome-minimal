# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder
RUN KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio: Configuração do sistema e imagem final
FROM quay.io/fedora/fedora-bootc:44 AS final
# 1. Instalação do kernel e módulos extras e crioação de diretórios de trabalho
RUN mkdir -vp /var/roothome /data /var/home && \
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-modules-extra-${kver}" && \
    dnf5 clean all && \
    rm -rfv /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 2. Instalação dos módulos e drivers NVIDIA compilados
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm ./
RUN dnf5 download nvidia-kmod-common nvidia-driver-cuda && \
    rpm -vi --nodeps nvidia-kmod-common*.rpm && \
    rpm -vi --nodeps nvidia-driver-cuda*.rpm && \
    dnf5 -y install ./kmod-nvidia-*.rpm && \
    rm -rvf kmod-nvidia-*.rpm nvidia-kmod-common*.rpm nvidia-driver-cuda*.rpm && \
    dnf5 clean all && \
    rm -rfv /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 3. Pacotes base do ambiente gráfico GNOME Minimalista
RUN dnf5 install gnome-shell --setopt=install_weak_deps=False -y && \
    dnf5 clean all && \
    rm -rfv /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

# 4. Listas de pacotes personalizadas
# Copiadas separadamente para evitar a invalidação do cache do GNOME e NVIDIA
COPY pacotes_necessarios pacotes_desktop /tmp/
RUN grep -v '^#' /tmp/pacotes_necessarios | tr '\n' ' ' | xargs dnf5 install -y && \
    grep -v '^#' /tmp/pacotes_desktop | tr '\n' ' ' | xargs dnf5 install -y && \
    dnf5 clean all && \
    rm -rfv /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/*

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