# Create chroot via tar -C chroot -c . | docker import - stripectf/chroot:v0
# Build via docker build -t stripectf/runtime:v0 .

FROM stripectf/chroot:v0
MAINTAINER Stripe CTF <ctf@stripe.com>

# RUN apt-get install <what do we want>

# Good enough for now
WORKDIR /development
CMD ["/bin/bash"]

RUN mkdir -p /ctf3 /development

# Fake a FUSE installation (https://github.com/dotcloud/docker/issues/514)
# https://gist.github.com/henrik-muehe/6155333
RUN apt-get install -y libfuse2
RUN cd /tmp ; apt-get download fuse
RUN cd /tmp ; dpkg-deb -x fuse_* .
RUN cd /tmp ; dpkg-deb -e fuse_*
RUN cd /tmp ; rm fuse_*.deb
RUN cd /tmp ; echo -en '#!/bin/bash\nexit 0\n' > DEBIAN/postinst
RUN cd /tmp ; dpkg-deb -b . /fuse.deb
RUN cd /tmp ; dpkg -i /fuse.deb

# To deal with https://github.com/dotcloud/docker/issues/1024
RUN dpkg-divert --local --rename --add /sbin/initctl
RUN ln -s /bin/true /sbin/initctl

# Actually install java
RUN apt-get install -y openjdk-7-jre openjdk-7-jdk
RUN apt-get install -y net-tools libcurl4-openssl-dev iputils-ping sqlite3

# Install go deps
RUN apt-get install -y mercurial

RUN mkdir /skeleton

# Install go
RUN curl -o /tmp/go1.2.linux-amd64.tar.gz 'https://go.googlecode.com/files/go1.2.linux-amd64.tar.gz' && [ "$(sha256sum /tmp/go1.2.linux-amd64.tar.gz | head -c 64)" = "1252ca0aa0a96d53c0592fbc4ea9c9ff5c6b588169c92e08d06da9d89d9d91f2" ]
RUN tar -xf /tmp/go1.2.linux-amd64.tar.gz -C /usr/local
RUN rm /tmp/go1.2.linux-amd64.tar.gz
ADD bootstrap-go.sh /ctf3/bootstrap-go.sh
RUN chmod +x /ctf3/bootstrap-go.sh
RUN /ctf3/bootstrap-go.sh

# socat
RUN apt-get install -y socat

# Install nodejs
RUN curl -o /tmp/node-v0.10.23-linux-x64.tar.gz http://nodejs.org/dist/v0.10.23/node-v0.10.23-linux-x64.tar.gz && [ "$(sha1sum /tmp/node-v0.10.23-linux-x64.tar.gz | head -c 40)" = "4c7d17ae61c753750e8f5ae989e3d80f7c8f89ea" ]
RUN tar -xf /tmp/node-v0.10.23-linux-x64.tar.gz -C /usr/local
RUN mv /usr/local/node-v0.10.23-linux-x64 /usr/local/node
RUN rm /tmp/node-v0.10.23-linux-x64.tar.gz
ADD bootstrap-nodejs.sh /ctf/bootstrap-nodejs.sh
RUN chmod +x /ctf/bootstrap-nodejs.sh
RUN /ctf/bootstrap-nodejs.sh

# Beginning of user requested packages
RUN apt-get install -y sbcl cl-quicklisp pypy php5-cli ghc cabal-install \
      libboost1.53-dev  libboost-regex1.53-dev ruby-sinatra
RUN apt-get install -y erlang libncurses5-dev libghc-text-prof

# Cache nodejs dependencies
ADD node_modules/ /tmp/node_modules/
RUN /usr/local/node/bin/npm cache add /tmp/node_modules/http-proxy
RUN /usr/local/node/bin/npm cache add /tmp/node_modules/nopt
RUN /usr/local/node/bin/npm cache add /tmp/node_modules/seed-random
RUN /usr/local/node/bin/npm cache add /tmp/node_modules/underscore
RUN rm -r /tmp/node_modules/

# Packages
RUN apt-get install -y python-pip
RUN apt-get install -y python-dev
RUN apt-get install -y libcmph-dev libcmph-tools

# Bring back the sticky bit. I don't know where it went.
RUN chmod 1777 /tmp /var/tmp

# Scoring shim
ADD init.sh /ctf3/init.sh
RUN chmod 755 /ctf3/init.sh

# Shell for bootstrapping into the box
ADD shell.sh /ctf3/shell.sh
RUN chmod 755 /ctf3/shell.sh
