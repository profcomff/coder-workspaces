FROM node:18-bookworm

RUN apt-get update \
	&& apt-get install -y \
	curl \
	git \
	gh \
	sudo \
	vim \
	wget \
	zsh \
	build-essential \
	&& npm install -g pnpm \
	&& rm -rf /var/lib/apt/lists/*

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
	&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
	&& chmod 0440 /etc/sudoers.d/${USER} \
	&& usermod -s /bin/zsh ${USER}

USER ${USER}
WORKDIR /home/${USER}
ADD ./node.code-workspace /home/${USER}/node.code-workspace
RUN sudo chown -R ${USER} /home/${USER} \
	&& sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
