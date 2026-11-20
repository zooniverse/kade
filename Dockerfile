FROM ruby:3.3.14-slim-bookworm

WORKDIR /rails_app

RUN apt-get update && apt-get -y upgrade && \
    apt-get install --no-install-recommends -y \
        build-essential \
        # remove git once panoptes-client.rb is updated to >= v.0.4
        git \
        libpq-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ARG RAILS_ENV=production
ENV RAILS_ENV=$RAILS_ENV

ADD ./Gemfile /rails_app/
ADD ./Gemfile.lock /rails_app/

RUN bundle config --global jobs `cat /proc/cpuinfo | grep processor | wc -l | xargs -I % expr % - 1` && \
    if echo "development test" | grep -w "$RAILS_ENV"; then \
    bundle install; \
    else \
    # switch to new config syntax for non dev/test gem group installs
    bundle config set --local without 'development test'; \
    bundle install; \
    fi

ADD ./ /rails_app

RUN if echo "staging production" | grep -w "$RAILS_ENV"; then \
    bundle exec bootsnap precompile --gemfile app/ lib/; \
    fi

ARG REVISION=''
ENV REVISION=$REVISION

EXPOSE 80

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
