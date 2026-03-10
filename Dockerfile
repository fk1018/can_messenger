# syntax=docker/dockerfile:1

ARG RUBY_VERSION=4.0.1
FROM ruby:${RUBY_VERSION}-slim

ENV APP_HOME=/app \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

WORKDIR ${APP_HOME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

# Copy files needed to resolve and install gems first for better layer caching.
COPY Gemfile can_messenger.gemspec ./
COPY lib/can_messenger/version.rb lib/can_messenger/version.rb

RUN bundle install

COPY . .

CMD ["bash"]
