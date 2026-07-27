# Primeiro estágio: Construção dos módulos NVIDIA (akmods)
FROM quay.io/fedora/fedora-bootc:44 AS builder
RUN KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf5 -y install "kernel-devel-${KERNEL_VERSION}" wget && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda && \
    akmods --force --kernels "$KERNEL_VERSION"

# Segundo estágio: Configuração do sistema e imagem final
FROM quay.io/fedora/fedora-bootc:44 AS final

# 1. Estrutura de diretórios do sistema e links simbólicos (compatibilidade bootc)
RUN mkdir -vp /var/roothome /data /var/home && \
    rm -rf /opt && mkdir -vp /var/opt && ln -vs /var/opt /opt && \
    mkdir -vp /var/usrlocal && mv -v /usr/local/* /var/usrlocal/ 2>/dev/null || true && \
    rm -rf /usr/local && ln -vs /var/usrlocal /usr/local

# 2. Instalação dos módulos NVIDIA compilados
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm /tmp/kmod/
RUN dnf5 install -y nvidia-kmod-common nvidia-driver-cuda /tmp/kmod/*.rpm && \
    rm -rf /tmp/kmod && \
    dnf5 clean all

# 3. Instalação Unificada: Kernel Extra + GNOME + Pacotes Personalizados
COPY pacotes_necessarios pacotes_desktop /tmp/
RUN KVER="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    PKGS_BASE=$(grep -v '^#' /tmp/pacotes_necessarios | tr '\n' ' ') && \
    PKGS_DESK=$(grep -v '^#' /tmp/pacotes_desktop | tr '\n' ' ') && \
    dnf5 install -y --setopt=install_weak_deps=False \
        "kernel-modules-extra-${KVER}" \
        gnome-shell \
        $PKGS_BASE \
        $PKGS_DESK && \
    rm -f /tmp/pacotes_necessarios /tmp/pacotes_desktop && \
    dnf5 clean all

# 4. Cópia Direta de Arquivos de Configuração e Scripts (Modificações Frequentes)
COPY zram-generator.conf /etc/systemd/zram-generator.conf
COPY vconsole.conf /etc/vconsole.conf
COPY locale.conf /etc/locale.conf
COPY 10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml
COPY post-install.sh /usr/bin/post-install.sh
COPY post-install.service /usr/lib/systemd/system/post-install.service

# 5. Ativação de Serviços e Limpeza Final
RUN chmod +x /usr/bin/post-install.sh && \
    systemctl enable post-install.service && \
    systemctl mask systemd-remount-fs.service && \
    systemctl mask akmods-keygen@akmods-keygen.service && \
    systemctl enable libvirtd.service && \
    systemctl enable spice-vdagentd.service && \
    rm -rf /var/cache/* /var/lib/dnf/* /var/log/* /tmp/* /var/tmp/* /var/roothome/.*

# 6. Validação do bootc
RUN bootc container lint