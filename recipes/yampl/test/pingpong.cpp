// A client and a server process exchanging a message over each of yampl's transports
// (ZeroMQ, pipes and shared memory). Adapted from yampl's tests/dest.cpp.
#include "yampl/SocketFactory.h"
#include "yampl/pipe/SocketFactory.h"
#include "yampl/shm/SocketFactory.h"
#include "yampl/zeromq/SocketFactory.h"

#include <sys/wait.h>
#include <unistd.h>

#include <cstring>
#include <iostream>
#include <string>

using namespace yampl;

static void client(ISocketFactory* factory, const Channel& channel) {
  ISocket* socket = factory->createClientSocket(channel, "client");
  char buffer[100];
  socket->send("ping");
  socket->recv(buffer);
  if (std::strcmp(buffer, "pong") != 0) _exit(1);
  delete socket;
}

static void server(ISocketFactory* factory, const Channel& channel) {
  ISocket* socket = factory->createServerSocket(channel);
  char buffer[100];
  std::string dest;
  socket->recv(buffer, dest);
  socket->sendTo(dest, "pong");
  delete socket;
}

int main() {
  const pid_t pid = fork();
  if (pid == 0) {
    client(new zeromq::SocketFactory(), Channel("zmq", LOCAL));
    client(new pipe::SocketFactory(), Channel("pipe", LOCAL_PIPE));
    client(new shm::SocketFactory(), Channel("shm", LOCAL_SHM));
    _exit(0);
  }
  server(new zeromq::SocketFactory(), Channel("zmq", LOCAL));
  server(new pipe::SocketFactory(), Channel("pipe", LOCAL_PIPE));
  server(new shm::SocketFactory(), Channel("shm", LOCAL_SHM));
  int status = 0;
  waitpid(pid, &status, 0);
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return 1;
  std::cout << "ping-pong over zeromq, pipe and shm: ok" << std::endl;
  return 0;
}
