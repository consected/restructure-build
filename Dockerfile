FROM amazonlinux:2023

LABEL maintainer=phil.ayres@consected.com

COPY build-container.sh /root/build-container.sh
COPY shared/default-ruby-version.sh /shared/default-ruby-version.sh
COPY shared/lib/rbenv.sh /shared/lib/rbenv.sh

RUN /root/build-container.sh

CMD ["/shared/build-restructure.sh"]

