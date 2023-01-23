FROM ruby:2.7.3

RUN apt-get update -qq && apt-get install -y build-essential

ENV APP_HOME /app
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* $APP_HOME/
RUN bundle install --without development test
RUN bundle update --bundler

ADD . $APP_HOME

ENV PORT=9898
ENTRYPOINT bundle exec rackup --host 0.0.0.0 -p $PORT
