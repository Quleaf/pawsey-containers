FROM quay.io/pawsey/rocm-mpich-base:rocm5.6.0-mpich3.4.3-ubuntu22

ENV _GLIBCXX_USE_CXX11_ABI=1
ENV USE_CUDA=0
ENV USE_ROCM=1
ENV CXX=g++
ENV CC=gcc
ENV CXXFLAGS=-std=c++17
ENV PYTORCH_ROCM_ARCH=gfx90a	
ENV LD_LIBRARY_PATH=/opt/rocm/llvm/lib:$LD_LIBRARY_PATH

RUN	apt -y install libopenblas-dev "libpng*" "libjpeg-turbo*" libjpeg-dev libpng-dev \
	&& (! [ -e /tmp/build ] || rm -rf /tmp/build) \
	&& mkdir /tmp/build && cd /tmp/build \
	# install eigen
	&& wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz \
	&& tar xf eigen-3.4.0.tar.gz \
	&& cd eigen-3.4.0 \
	&& mkdir build \
	&& cd build \
	&& cmake .. \
	&& make -j 16 \
	&& make install

RUN     pip3 install mpmath urllib3 typing-extensions sympy pillow numpy networkx MarkupSafe idna fsspec filelock charset-normalizer certifi requests pytorch-triton-rocm jinja2 --index-url https://download.pytorch.org/whl/rocm5.6 --no-dependencies

ENV ROCM_PATH=/opt/rocm

RUN	cd /tmp/build \
	&& git clone --branch v2.2.0 --recursive https://github.com/pytorch/pytorch \
	&& cd pytorch \
	&& grep -R . -e "MPI_CXX" | cut -f1 -d: | xargs -n1 sed -i -e "s/MPI_CXX/MPI_C/g" \
	# if you are updating an existing checkout \
	&& git submodule sync \
	&& git submodule update --init --recursive \
	# sets "USE_SYSTEM_EIGEN_INSTALL=ON"
	&& sed -i -e '270d' -e '269a ON)' CMakeLists.txt \
	# Install deps	
	&& python3 -m pip install -r requirements.txt \
        && sed -i -e '3d' -e '2 a pip install --index-url https://download.pytorch.org/whl/nightly/ "pytorch-triton==2.2.0+e28a256d71" ' scripts/install_triton_wheel.sh\
	&& make triton\
	&& python3 tools/amd_build/build_amd.py\
	&& python3 setup.py install 

# Install torch vision
RUN     cd /tmp/build \
        && git clone --branch v0.17.0 https://github.com/pytorch/vision.git \
        && cd vision \
        && python3 setup.py install

# Install torch audio
ARG CXX=hipcc
ARG ROCRAND_PATH=/opt/rocm
ARG HIPRAND_PATH=/opt/rocm
ARG ROCBLAS_PATH=/opt/rocm
ARG MIOPEN_PATH=/opt/rocm
ARG ROCFFT_PATH=/opt/rocm
ARG HIPFFT_PATH=/opt/rocm
ARG HIPSPARSE_PATH=/opt/rocm
ARG RCCL_PATH=/opt/rocm
ARG ROCPRIM_PATH=/opt/rocm
ARG HIPCUB_PATH=/opt/rocm
ARG ROCTHRUST_PATH=/opt/rocm

RUN     cd /tmp/build \
        && git clone --branch v2.2.0 https://github.com/pytorch/audio.git \
        && cd audio \
        && sed -i '149,150d' cmake/LoadHIP.cmake \
        && python3 setup.py install


RUN	[ -e /tmp/build ] && rm -rf /tmp/build