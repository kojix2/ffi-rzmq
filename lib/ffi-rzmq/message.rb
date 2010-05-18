
module ZMQ

  ZMQ_MSG_INIT_SIZE_STR = 'zmq_msg_init_size'.freeze
  ZMQ_MSG_INIT_DATA_STR = 'zmq_msg_init_data'.freeze
  ZMQ_MSG_INIT_STR = 'zmq_msg_init'.freeze
  ZMQ_MSG_CLOSE_STR = 'zmq_msg_close'.freeze
  ZMQ_MSG_COPY_STR = 'zmq_msg_copy'.freeze
  ZMQ_MSG_MOVE_STR = 'zmq_msg_move'.freeze
  ZMQ_MSG_SIZE_STR = 'zmq_msg_size'.freeze

  # When you really need to control when data is allocated and released,
  # use this class. Otherwise, use its smarter brother #Message.
  #
  # The constructor optionally takes a string as an argument. It will
  # copy this string to native memory in preparation for transmission.
  # So, don't pass a string unless you intend to send it. Internally it
  # calls #copy_in_string.
  #
  # Call #close when done with this object to release buffers.
  #
  # (Not really zero-copy. Ruby makes this near impossible.)
  #
  class UnmanagedMessage
    include ZMQ::Util

    def initialize message = nil
      # allocate our own pointer so that we can tell it to *not* zero out
      # the memory; it's pointless work since the library is going to
      # overwrite it anyway.
      @pointer = FFI::MemoryPointer.new LibZMQ::Msg.size, 1, false
      @struct = LibZMQ::Msg.new @pointer

      if message
        copy_in_string message
      else
        # initialize an empty message structure to receive a message
        result_code = LibZMQ.zmq_msg_init @struct
        error_check ZMQ_MSG_INIT_STR, result_code
      end
    end
    
    def copy_in_string string
      # add extra byte to null-terminate
      len = string.size + 1
      data_buffer = LibC.malloc len
      data_buffer.put_string 0, string

      # keep that extra byte on the end a secret :)
      # we want to send only the bytes of the string and not its terminator;
      # the buffer already knows its size so we can reconstruct it
      # on the far side. Unnecessary to transmit.
      result_code = LibZMQ.zmq_msg_init_data @struct.pointer, data_buffer, len - 1, LibZMQ::MessageDeallocator, nil
      error_check ZMQ_MSG_INIT_DATA_STR, result_code
    end
    
    def copy_in_bytes bytes, len
      
    end

    # Provides the memory address of the +zmq_msg_t+ struct. Used mostly for
    # passing to other methods accessing the underlying library that
    # require a real data address.
    #
    def address
      @struct.pointer
    end
    alias :pointer :address

    def copy source
      result_code = LibZMQ.zmq_msg_copy @struct.pointer, source.address
      error_check ZMQ_MSG_COPY_STR, result_code
    end

    def move source
      result_code = LibZMQ.zmq_msg_copy @struct.pointer, source.address
      error_check ZMQ_MSG_MOVE_STR, result_code
    end

    # Provides the size of the data buffer for this +zmq_msg_t+ C struct.
    #
    def size
      LibZMQ.zmq_msg_size @struct.pointer
    end

    # Returns a pointer to the data buffer.
    # This pointer should *never* be freed. It will automatically be freed
    # when the +message+ object goes out of scope and gets garbage
    # collected.
    #
    def data
      LibZMQ.zmq_msg_data @struct.pointer
    end

    # Returns the data buffer as a string.
    #
    # Note: If this is binary data, it won't print very prettily.
    #
    def copy_out_string
      data.read_string(size)
    end

    # Manually release the message struct and its associated buffers.
    #
    def close
      LibZMQ.zmq_msg_close @struct.pointer
      @pointer.free
      @struct = nil
    end
    
  end # class UnmanagedMessage

  # The ruby equivalent of the +zmq_msg_t+ C struct. Access the underlying
  # memory buffer and the buffer size using the #data and #size methods
  # respectively.
  #
  # It is recommended that this class be composed inside another class for
  # access to the underlying buffer. The outer wrapper class can provide
  # nice accessors for the information in the data buffer; a clever
  # implementation can probably lazily encode/decode the data buffer
  # on demand. Lots of protocols send more information than is strictly
  # necessary, so only decode (copy from the 0mq buffer to Ruby) that
  # which is necessary.
  #
  # When you are done using the message object, just let it go out of
  # scope to release the memory. During the next garbage collection run
  # it will call the equivalent of #LibZMQ.zmq_msg_close to release
  # all buffers. Obviously, this automatic collection of message objects
  # comes at the price of a larger memory footprint (for the
  # finalizer proc object) and lower performance. If you wanted blistering
  # performance, Ruby isn't there just yet.
  #
  #  class MyMessage
  #    def initialize msg_struct = nil
  #      @msg_t = msg_struct ? msg_struct : ZMQ::Message.new
  #    end
  #
  #    def size() @size = @msg_t.size; end
  #
  #    def decode
  #      @decoded_data = JSON.parse(@msg_t.data_as_string)
  #    end
  #
  #    def field1
  #      @field1 ||= decode[:field1]
  #    end
  #
  #    def field2
  #      @field2 ||= decode[:field2]
  #    end
  # ---
  #
  #  message = Message.new
  #  successful_read = socket.recv message
  #  message = MyMessage.new message if successful_read
  #  puts "field1 is #{message.field1}"
  #
  class Message < UnmanagedMessage
    def initialize message = nil
      super

      define_finalizer
    end

    # Has no effect. This class has automatic memory management via a
    # finalizer.
    def close() end

    private

    def define_finalizer
      ObjectSpace.define_finalizer(self, self.class.close(@struct, @pointer))
    end

    # Message finalizer
    # Note that there is no error checking for the call to #zmq_msg_close.
    # This is intentional. Since this code runs as a finalizer, there is no
    # way to catch a raised exception anywhere near where the error actually
    # occurred in the code, so we just ignore deallocation failures here.
    def self.close struct, pointer
      Proc.new do
        # release the data buffer
        LibZMQ.zmq_msg_close struct.pointer
        pointer.free
        struct = nil
      end
    end
  end # class Message

end # module ZMQ
