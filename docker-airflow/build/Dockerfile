FROM ghcr.io/profcomff/dwh-airflow:v2024.05.10

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
	&& rm -rf /var/lib/apt/lists/*

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
	&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
	&& chmod 0440 /etc/sudoers.d/${USER} \
	&& usermod -s /bin/zsh ${USER}

USER ${USER}
WORKDIR /home/${USER}
ADD ./airflow.code-workspace /home/${USER}/airflow.code-workspace
RUN sudo chown -R ${USER} /home/${USER} \
	&& sudo mkdir -p /airflow \
	&& sudo chown -R ${USER} /airflow \
	&& sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

ENV AIRFLOW_ENV=DEV
ENV AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres:5432/airflow
ENV DB_DSN=postgresql+psycopg2://postgres:postgres@postgres:5432/postgres

CMD ["/bin/zsh"]
