FROM ubuntu:22.04

ENV DEBIAN_FRONTEND="noninteractive"

ARG	MPICH_CONFIGURE_OPTIONS="--enable-fast=all,O3 --enable-fortran --enable-romio --prefix=/usr --with-device=ch4:ofi CC=gcc CXX=g++ FFLAGS=-fallow-argument-mismatch FC=gfortran"
ARG	MPICH_MAKE_OPTIONS="-j12"
ARG	MPICH_VERSION=3.4.3
ARG LIBFABRIC_VERSION=1.18.1
ARG ROCM_VERSION=5.7
ARG ROCM_INSTALLER_VERION=5.7.50700-1

# Install required packages and dependencies
RUN	ln -s /usr/share/zoneinfo/Australia/Perth /etc/localtime \
	&& apt -y update \
	&& apt -y install build-essential wget gnupg gnupg2 software-properties-common  \
		git vim gfortran libtool libstdc++-12-dev python3-venv ninja-build \
 		libnuma-dev python3-dev \
	&& apt -y remove --purge --auto-remove cmake \
	&& wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null\
		| gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null \
	&& apt-add-repository -y "deb https://apt.kitware.com/ubuntu/ jammy-rc main" \
	&& apt -y update \
	&& apt -y install cmake

# Build and install libfabric
RUN (if [ -e /tmp/build ]; then rm -rf /tmp/build; fi;) \
	&& mkdir -p /tmp/build \
	&& cd /tmp/build \
	&& wget https://github.com/ofiwg/libfabric/archive/refs/tags/v${LIBFABRIC_VERSION}.tar.gz \
	&& tar xf v${LIBFABRIC_VERSION}.tar.gz \
	&& cd libfabric-${LIBFABRIC_VERSION} \ 
	&& ./autogen.sh \
	&& ./configure \
	&& make -j 16 \ 
	&& make install

# Build MPICH
RUN	mkdir -p /tmp/mpich-build \
	&& cd /tmp/mpich-build \
	&& wget http://www.mpich.org/static/downloads/${MPICH_VERSION}/mpich-${MPICH_VERSION}.tar.gz \
	&& tar xvzf mpich-${MPICH_VERSION}.tar.gz \
	&& cd mpich-${MPICH_VERSION}  \
	&& ./configure ${MPICH_CONFIGURE_OPTIONS} \
	&& make ${MPICH_MAKE_OPTIONS} && make install \
	&& ldconfig \
	&& cp -p /tmp/mpich-build/mpich-${MPICH_VERSION}/examples/cpi /usr/bin/ \
	&& cd / \
	&& rm -rf /tmp/mpich-build

# Install ROCm
RUN cd /tmp/build \
    && wget https://bootstrap.pypa.io/get-pip.py \
    && python3 get-pip.py \
	&& wget https://repo.radeon.com/amdgpu-install/${ROCM_VERSION}/ubuntu/jammy/amdgpu-install_${ROCM_INSTALLER_VERION}_all.deb \
	&& apt -y install ./amdgpu-install_${ROCM_INSTALLER_VERION}_all.deb \
	&& amdgpu-install -y --usecase=hiplibsdk,rocm,hip,opencl \
    && cd /tmp/build

# Install aws-ofi-rccl
RUN git clone https://github.com/ROCmSoftwarePlatform/aws-ofi-rccl.git \
	&& cd aws-ofi-rccl \
	&& ./autogen.sh \
	&& ./configure --prefix=/usr --with-mpi=/usr --with-libfabric=/usr --with-hip=/opt/rocm --with-rccl=/opt/rocm \
	&& make -j 16 \
	&& make install \
    && cd /tmp \
	&& rm -rf /tmp/build

# Singularity: will execute scripts in /.singularity.d/env/ at startup (and ignore those in /etc/profile.d/).
#              Standard naming of "environment" scripts is 9X-environment.sh
RUN mkdir -p /.singularity.d/env/
RUN echo "export NCCL_DEBUG=INFO" >> /.singularity.d/env/91-environment.sh && \
	echo "export NCCL_SOCKET_IFNAME=hsn"  >> /.singularity.d/env/91-environment.sh && \
	echo "export CXI_FORK_SAFE=1"  >> /.singularity.d/env/91-environment.sh && \
	echo "export CXI_FORK_SAFE_HP=1" >> /.singularity.d/env/91-environment.sh && \
	echo "export FI_CXI_DISABLE_CQ_HUGETLB=1" >> /.singularity.d/env/91-environment.sh
