# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder
RUN KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio: Configuração do sistema e imagem final
FROM quay.io/fedora/fedora-bootc:44 AS final

# Estrutura de diretórios necessários para home, opt e usr/local
RUN mkdir -vp /var/roothome /data /var/home && \
    rm -rf /opt && mkdir -vp /var/opt && ln -vs /var/opt /opt && \
    mkdir -vp /var/usrlocal && \
    rm -rf /usr/local && ln -vs /var/usrlocal /usr/local && \

# 1. Instalação dos módulos e drivers NVIDIA compilados (Via dnf download + rpm em /tmp)
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm /tmp/
RUN cd /tmp && \
    dnf5 download nvidia-kmod-common nvidia-driver-cuda && \
    rpm -vi --nodeps nvidia-kmod-common*.rpm && \
    rpm -vi --nodeps nvidia-driver-cuda*.rpm && \
    dnf5 -y install ./kmod-nvidia-*.rpm && \
    dnf5 clean all && \
    rm -rfv /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/* /var/roothome/.*

# 2. Instalação Unificada do Kernel Extra, GNOME e Pacotes das Listas (com --nodocs)
COPY pacotes_necessarios pacotes_desktop /tmp/
RUN dnf5 install -y --nodocs --setopt=install_weak_deps=False gnome-shell "kernel-modules-extra-$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    grep -h -v '^#' /tmp/pacotes_necessarios /tmp/pacotes_desktop | xargs dnf5 install -y --nodocs && \
    rm -f /tmp/pacotes_necessarios /tmp/pacotes_desktop && \
    dnf5 clean all

# 3. Cópia dos arquivos de configuração e scripts
COPY zram-generator.conf /etc/systemd/zram-generator.conf
COPY vconsole.conf /etc/vconsole.conf
COPY locale.conf /etc/locale.conf
COPY 10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml
COPY post-install.sh /usr/bin/post-install.sh
COPY post-install.service /usr/lib/systemd/system/post-install.service

# 4. Estrutura de diretórios, compatibilidade bootc, permissões e serviços
RUN chmod +x /usr/bin/post-install.sh && \
    systemctl enable post-install.service && \
    systemctl mask systemd-remount-fs.service && \
    systemctl mask akmods-keygen@akmods-keygen.service && \
    systemctl enable libvirtd.service && \
    systemctl enable spice-vdagentd.service && \
    rm -rf /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/* /var/roothome/.*

# 5. Validação do bootc
RUN bootc container lint