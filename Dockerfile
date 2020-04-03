FROM ruby:2.6.3

RUN apt-get update -qq && apt-get install -y build-essential

ENV APP_HOME /app
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* $APP_HOME/
RUN bundle install --without development test

ADD . $APP_HOME

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "-p", "9898"]