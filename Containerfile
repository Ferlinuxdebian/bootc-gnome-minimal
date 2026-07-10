# Primeiro estágio para build driver da nvidia
ARG SOURCE_DATE_EPOCH=1719840000

FROM quay.io/fedora/fedora-bootc:44 AS builder
ARG SOURCE_DATE_EPOCH
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}
RUN dnf5 upgrade -y 'kernel*' --refresh && \
    dnf5 -y install kernel-devel wget --refresh && \
    KERNEL_VERSION="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    wget -O /etc/yum.repos.d/fedora-nvidia-580.repo \
    https://negativo17.org/repos/fedora-nvidia-580.repo && \
    dnf5 install -y nvidia-driver nvidia-driver-cuda --refresh && \
    akmods --force --kernels "$KERNEL_VERSION"

# Imagem final 
FROM quay.io/fedora/fedora-bootc:44 AS final
ARG SOURCE_DATE_EPOCH
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}
LABEL ostree.bootable="true"
LABEL containers.bootc="1"

# Repo NVIDIA e RPM do kmod vêm do builder, sem novo download
COPY --from=builder /etc/yum.repos.d/fedora-nvidia-580.repo /etc/yum.repos.d/
COPY --from=builder /var/cache/akmods/nvidia/kmod-nvidia*.rpm ./
COPY 10-nvidia-args.toml locale.conf post-install.sh pacotes_desktop pacotes_necessarios post-install.service vconsole.conf zram-generator.conf ./

RUN mkdir -vp /var/roothome /data /var/home && \
    dnf5 -y install kernel-modules-extra && \
    printf 'omit_dracutmodules+=" nfs "\nomit_drivers+=" nfs nfsv3 nfsv4 nfs_acl nfs_common sunrpc rxrpc rpcrdma auth_rpcgss rpcsec_gss_krb5 "\n' | tee /etc/dracut.conf.d/no-nfs.conf && \
    kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dracut -f --reproducible /usr/lib/modules/${kver}/initramfs.img ${kver} && \
    mv -v zram-generator.conf /etc/systemd/ && \
    dnf5 download nvidia-driver-cuda nvidia-kmod-common & \
    rpm -i --nodeps ./nvidia-driver-cuda*.rpm ./nvidia-kmod-common*.rpm && \
    dnf5 -y install ./kmod-nvidia-*.rpm && \
    rm -rvf /opt && mkdir -vp /var/opt && ln -vs /var/opt /opt && \
    mkdir -vp /var/usrlocal && mv -v /usr/local/* /var/usrlocal/ && \
    rm -rvf /usr/local && ln -vs /var/usrlocal /usr/local && \
    mv -v vconsole.conf /etc/vconsole.conf && \
    mv -v locale.conf /etc/locale.conf && \
    mv -v 10-nvidia-args.toml /usr/lib/bootc/kargs.d/10-nvidia-args.toml && \
    mv -v post-install.sh /usr/bin/post-install.sh && \
    mv -v post-install.service /usr/lib/systemd/system/post-install.service && \
    chmod +x /usr/bin/post-install.sh && \
    systemctl enable post-install.service && \
    rm -rvf kmod-nvidia-*.rpm && \
    dnf5 clean all && \
    rm -rfv /var/cache/dnf /var/cache/libdnf /var/log/* /var/tmp/* /tmp/* nvidia-driver-cuda*.rpm nvidia-kmod-common*.rpm

# instalalação do gnome shell minimalista
RUN dnf5 install gnome-shell --setopt=install_weak_deps=False -y && \
    dnf5 clean all && \
    rm -rfv /var/cache/dnf /var/cache/libdnf /var/log/* /var/tmp/* /tmp/*

# Instalaçãod do pacotes de desktop e demais necessários
RUN grep -v '^#' pacotes_necessarios | tr '\n' ' ' | xargs dnf5 install -y && \
    grep -v '^#' pacotes_desktop | tr '\n' ' ' | xargs dnf5 install -y && \
    systemctl mask systemd-remount-fs.service && \
    systemctl mask akmods-keygen@akmods-keygen.service && \
    systemctl enable libvirtd.service && \
    systemctl enable spice-vdagentd.service && \
    rm -fv pacotes_necessarios pacotes_desktop && \
    dnf5 clean all && \
    rm -rfv /var/cache/dnf /var/cache/libdnf /var/log/* /var/tmp/* /tmp/* \
    /var/usrlocal/share/applications/mimeinfo.cache \
    /var/roothome/.* && \
    bootc container lint

# Chunkah para otimizar as layers 
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
