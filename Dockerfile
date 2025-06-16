ARG BUILD_BOARD

####################################################################################################
################################## Stage: builder ##################################################

FROM balenalib/"$BUILD_BOARD"-debian:bullseye-build-20230530 AS builder

WORKDIR /opt/

COPY pyproject.toml poetry.lock README.md ./
COPY lib/ lib/
COPY gatewayconfig/ gatewayconfig/
COPY *.sh ./

ENV PATH="/opt/venv/bin:$PATH"

RUN install_packages \
        python3-minimal \
        python3-pip \
        wget \
        python3-venv \
        libgirepository1.0-dev \
        gcc \
        libcairo2-dev \
        pkg-config \
        python3-dev \
        libdbus-1-dev \
        gir1.2-gtk-3.0 \
        swig \
        git \
    && git clone https://github.com/joan2937/lg.git /tmp/lgpio \
    && cd /tmp/lgpio && make \
    && cd /opt && python3 -m venv /opt/venv \
    && pip install --no-cache-dir wheel \
    && pip install --no-cache-dir poetry==1.5.1 \
    && poetry install --no-cache --no-root \
    && poetry build \
    && pip install --no-cache-dir dist/hm_config-1.0.tar.gz

####################################################################################################
################################### Stage: runner ##################################################

FROM balenalib/"$BUILD_BOARD"-debian-python:bullseye-run-20230530 AS runner

WORKDIR /opt/

RUN install_packages \
        bluez \
        wget \
        libdbus-1-3 \
        network-manager \
        python3-gi \
        python3-venv \
        libgpiod2 \
        make \
        gcc

COPY *.sh ./
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /tmp/lgpio /tmp/lgpio  # bring compiled lgpio source for native install

ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONPATH="/opt:$PYTHONPATH"
ENV GPIOZERO_PIN_FACTORY=lgpio

# Now install lgpio on the native arm64 host
RUN cd /tmp/lgpio && make install && ldconfig && rm -rf /tmp/lgpio

# Set up MRAA (needed for GPIO support on some platforms)
RUN export DISTRO=bullseye-stable && \
    echo "deb https://apt.radxa.com/$DISTRO/ ${DISTRO%-*} main" | tee -a /etc/apt/sources.list.d/apt-radxa-com.list && \
    wget -nv -O - apt.radxa.com/$DISTRO/public.key | apt-key add - && \
    apt-get update && \
    apt-get install --no-install-recommends -y libmraa && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PYTHONPATH="$PYTHONPATH:/usr/local/lib/python3.9/dist-packages"

ENTRYPOINT ["/opt/start-gateway-config.sh"]
