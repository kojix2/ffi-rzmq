
module ZMQ

  ZMQ_SOCKET_STR = 'zmq_socket'.freeze unless defined? ZMQ_SOCKET_STR
  ZMQ_SETSOCKOPT_STR = 'zmq_setsockopt'.freeze
  ZMQ_BIND_STR = 'zmq_bind'.freeze
  ZMQ_CONNECT_STR = 'zmq_connect'.freeze
  ZMQ_SEND_STR = 'zmq_send'.freeze
  ZMQ_RECV_STR = 'zmq_recv'.freeze

  class Socket
    include ZMQ::Util

    attr_reader :socket

    # By default, this class uses ZMQ::Message for regular Ruby
    # memory management. 
    #
    # Pass {:unmanaged => true} as +opts+ to override the
    # default and have the pleasure of calling
    # UnmanagedMessage#close all by yourself.
    #
    # +type+ can be one of ZMQ::REQ, ZMQ::REP, ZMQ::PUB, 
    # ZMQ::SUB, ZMQ::PAIR, ZMQ::UPSTREAM, ZMQ::DOWNSTREAM,
    # ZMQ::XREQ or ZMQ::XREP.
    #
    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def initialize context_ptr, type, opts = {}
      defaults = {:unmanaged => false}
      message_type defaults.merge(opts)

      @socket = LibZMQ.zmq_socket context_ptr, type
      error_check ZMQ_SOCKET_STR, @socket.nil? ? 1 : 0
    end

    # Set the queue options on this socket.
    #
    # Valid +option_name+ values that take a numeric +option_value+ are:
    #  ZMQ::HWM
    #  ZMQ::LWM
    #  ZMQ::SWAP
    #  ZMQ::AFFINITY
    #  ZMQ::RATE
    #  ZMQ::RECOVERY_IVL
    #  ZMQ::MCAST_LOOP
    #
    # Valid +option_name+ values that take a string +option_value+ are:
    #  ZMQ::IDENTITY
    #  ZMQ::SUBSCRIBE
    #  ZMQ::UNSUBSCRIBE
    #
    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def setsockopt option_name, option_value, option_len = nil
      begin
        case option_name
        when HWM, LWM, SWAP, AFFINITY, RATE, RECOVERY_IVL, MCAST_LOOP
          option_value_ptr = LibC.malloc option_value.size
          option_value_ptr.write_long option_value

        when IDENTITY, SUBSCRIBE, UNSUBSCRIBE
          # note: not checking errno for failed memory allocations :(
          option_value_ptr = LibC.malloc option_value.size
          option_value_ptr.write_string option_value

        else
          # we didn't understand the passed option argument
          # will force a raise due to EINVAL being non-zero
          error_check ZMQ_SETSOCKOPT_STR, EINVAL
        end

        result_code = LibZMQ.zmq_setsockopt @socket, option_name, option_value_ptr, option_len || option_value.size
        error_check ZMQ_SETSOCKOPT_STR, result_code
      ensure
        LibC.free option_value_ptr unless option_value_ptr.null?
      end
    end

    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def bind address
      result_code = LibZMQ.zmq_bind @socket, address
      error_check ZMQ_BIND_STR, result_code
    end

    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def connect address
      result_code = LibZMQ.zmq_connect @socket, address
      error_check ZMQ_CONNECT_STR, result_code
    end

    # Queues the message for transmission. Message is assumed to be an instance or
    # subclass of #Message.
    #
    # +flags+ may take two values:
    # * 0 (default) - blocking operation
    # * ZMQ::NOBLOCK - non-blocking operation
    #
    # Returns true when the message was successfully enqueued.
    # Returns false when the message could not be enqueued *and* +flags+ is set
    # with ZMQ::NOBLOCK.
    #
    # The application code is responsible for handling the +message+ object lifecycle
    # when #send return ZMQ::NOBLOCK or it raises an exception. The #send method
    # does not take ownership of the +message+ and its associated buffers.
    #
    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def send message, flags = 0
      result_code = LibZMQ.zmq_send @socket, message.address, flags

      # when the flag isn't set, do a normal error check
      # when set, check to see if the message was successfully queued
      queued = flags.zero? ? error_check(ZMQ_SEND_STR, result_code) : error_check_nonblock(result_code)

      # true if sent, false if failed/EAGAIN
      queued
    end

    # Helper method to make a new #Message instance out of the +message_string+ passed
    # in for transmission.
    #
    # +flags+ may be ZMQ::NOBLOCK.
    #
    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def send_string message_string, flags = 0
      message = @sender_klass.new
      message.copy_in_string message_string
      result = send message, flags
      message.close
      result
    end

    # Dequeues a message from the underlying queue. By default, this is a blocking operation.
    #
    # +flags+ may take two values:
    #  0 (default) - blocking operation
    #  ZMQ::NOBLOCK - non-blocking operation
    #
    # Returns a true when it successfully dequeues one from the queue.
    # Returns nil when a message could not be dequeued *and* +flags+ is set
    # with ZMQ::NOBLOCK.
    #
    # The application code is responsible for handling the +message+ object lifecycle
    # when #recv returns ZMQ::NOBLOCK or it raises an exception. The #recv method
    # does not take ownership of the +message+ and its associated buffers.
    #
    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def recv message, flags = 0
      result_code = LibZMQ.zmq_recv @socket, message.address, flags

      begin
        dequeued = flags.zero? ? error_check(ZMQ_RECV_STR, result_code) : error_check_nonblock(result_code)
      rescue ZeroMQError
        dequeued = false
        raise
      end

      dequeued ? true : nil
    end

    # Helper method to make a new #Message instance and convert its payload
    # to a string.
    #
    # +flags+ may be ZMQ::NOBLOCK.
    #
    # Can raise two kinds of exceptions depending on the error.
    # ContextError:: Raised when a socket operation is attempted on a terminated
    # #Context. See #ContextError.
    # SocketError:: See all of the possibilities in the docs for #SocketError.
    #
    def recv_string flags = 0
      message = @receiver_klass.new
      dequeued = recv message, flags

      if dequeued
        string = message.copy_out_string
        message.close
        string
      else
        nil
      end
    end


    private

    def message_type opts
      @sender_klass = opts[:unmanaged] ? ZMQ::UnmanagedMessage : ZMQ::Message
      @receiver_klass = opts[:unmanaged] ? ZMQ::UnmanagedMessage : ZMQ::Message
    end

  end # class Socket

end # module ZMQ
