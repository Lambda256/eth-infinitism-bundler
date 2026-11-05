FROM node:22.23.4-bookworm-slim
WORKDIR /app/
COPY dist/bundler.js /app/
COPY bundler.sh /app/
RUN chmod +rx /app/bundler.sh 
ENTRYPOINT [ "/app/bundler.sh" ]
