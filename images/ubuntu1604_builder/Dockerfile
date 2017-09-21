# Copyright (c) 2017 Wind River Systems Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

FROM ubuntu:16.04

MAINTAINER Konrad Scherer <Konrad.Scherer@windriver.com>

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confnew" -qy install --no-install-recommends \
    libc6:i386 libc6-dev-i386 libncurses5:i386 texi2html chrpath \
    diffstat subversion libgl1-mesa-dev libglu1-mesa-dev libsdl1.2-dev \
    texinfo gawk gcc gcc-multilib help2man g++ git-core python-gtk2 bash cpio \
    diffutils xz-utils make file screen wget time patch openssh-client \
    curl locales openssl ca-certificates iproute2 iputils-ping python3 repo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/man && \
    rm -rf /usr/share/doc && \
    rm -rf /usr/share/grub2 && \
    rm -rf /usr/share/texmf/fonts && \
    rm -rf /usr/share/texmf/doc && \
    /usr/sbin/locale-gen en_US.UTF-8 && \
    /usr/sbin/update-locale LANG=en_US.UTF-8 && \
    curl -s -L -o /bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 && \
    chmod +x /bin/dumb-init

# Add wrlbuild user and hack to bypass missing iptables program
RUN useradd --home-dir /home/wrlbuild --uid 1000 --gid 100 --shell /bin/bash wrlbuild && \
    echo '#!/bin/sh' > /tmp/iptables && echo 'exit 0' >> /tmp/iptables && chmod +x /tmp/iptables && \
    mv /tmp/iptables /sbin/iptables

ENTRYPOINT ["/bin/dumb-init"]

CMD ["/bin/bash"]

USER wrlbuild
