FROM dockerfile/nodejs

# dont rebuild npm install for each version
ADD package.json /tmp/package.json
RUN cd /tmp && npm install
RUN mkdir -p /opt/app && cp -a /tmp/node_modules /opt/app/

ADD . /opt/app
RUN cd /opt/app; npm install --production

EXPOSE 8000
CMD cd /opt/app/; PORT=8000 HOST=0.0.0.0 DATASYSTEM_HOST=$DATASYSTEM_PORT_9101_TCP_ADDR DATASYSTEM_PORT=$DATASYSTEM_PORT_9101_TCP_PORT npm start
