# filename network/socket.rb
#────────────────────────────────────────────────────────────────────────────
# ▶ Socket Library
# --------------------------------------------------------------------------
# Author    Ruby
# Version   1.8.1
#────────────────────────────────────────────────────────────────────────────
module Win32
  def copymem(len)
    buf = '\0' * len
    Win32API::RtlMoveMemory.call(buf, self, len)
    buf
  end
end

class Numeric
  include Win32
  def ref(length)
    buffer = "\\" * length
    Win32API::RtlMoveMemory.call(buffer, self, length)
    return buffer
  end
end

class String
  include Win32
  def ref(length)
    buffer = "\\" * length
    Win32API::RtlMoveMemory.call(buffer, self, length)
    return buffer
  end
end

class Network
  def self.call
    @closesocket = Win32API.new('ws2_32.dll', 'closesocket', 'p', 'l')
    @connect = Win32API.new('ws2_32.dll', 'connect', 'ppl', 'l')
    @gethostbyname = Win32API.new('ws2_32.dll', 'gethostbyname', 'p', 'l')
    @recv = Win32API.new('ws2_32.dll', 'recv', 'ppll', 'l')
    @select = Win32API.new('ws2_32.dll', 'select', 'lpppp', 'l')
    @send = Win32API.new('ws2_32.dll', 'send', 'ppll', 'l')
    @socket = Win32API.new('ws2_32.dll', 'socket', 'lll', 'l')
    @wsagetlasterror = Win32API.new('ws2_32.dll', 'WSAGetLastError', '', 'l')
  end
  
  def self.close
    ret = @closesocket.call($fd) rescue nil
    return ret
  end
  
  def self.connect(ip, port)
    check if ($fd = @socket.call(2, 1, 6)) == -1
    sockaddr = sockaddr_in(port, ip)
    ret = @connect.call($fd, sockaddr, sockaddr.size)
    check if ret == -1
    return ret
  end
  
  def self.gethostbyname(name)
    data = @gethostbyname.call(name)
    raise SocketError::ENOASSOCHOST if data == 0
    host = data.ref(16).unpack('LLssL')
    name = host[0].ref(256).unpack("c*").pack("c*").split("\0")[0]
    address_type = host[2]
    address_list = host[4].ref(4).unpack('L')[0].ref(4).unpack("c*").pack("c*")
    return [name, [], address_type, address_list]
    #ptr = @gethostbyname.call(name)
    #host = ptr.copymem(16).unpack('iissi')
    #p [host[0].copymem(16).split('\u0000')[0], [], host[2], host[4].copymem(4).unpack('l')[0].copymem(4)]
    #return [host[0].copymem(16).split('\u0000')[0], [], host[2], host[4].copymem(4).unpack('l')[0].copymem(4)]
  end
  
  def self.recv(len, flags = 0)
    buf = "\0" * len
    len = @recv.call($fd, buf, buf.size, flags)
    check if len == -1
    return buf, len
  end
  
  def self.select(timeout)
    ret = @select.call(1, [1, $fd].pack('ll'), 0, 0, [timeout, timeout * 1000000].pack('ll'))
    check if ret == -1
    return ret
  end
  
  def self.send(msg, flags = 0)
    ret = @send.call($fd, msg, msg.size, flags)
    check if ret == -1
    return ret
  end
  
  def self.sockaddr_in(port, host)
    return [2, port].pack('sn') + gethostbyname(host)[3] + [].pack('x8')
  end
  
  def self.ready?
    if select(0) != 0
      return true
    else
      return false
    end
  end
  
  def self.check
    errno = @wsagetlasterror.call
    if errno == 10053
      desc = "연결이 사용자의 호스트 시스템에 의해 중단되었습니다."
    elsif errno == 10054
      desc = "서버에서 현재 연결을 강제로 끊었습니다."
    elsif errno == 10061
      desc = "서버가 열리지 않아서 연결이 불가능 합니다."
    elsif errno == 10065
      desc = "네트워크 장애등에 의해 서버와 연결이 불가능 합니다."
    else
      desc = "시스템이 판단할 수 없는 에러입니다."
    end
    print desc
    exit
  end
end

#===============================================================================
# ** Socket
#-------------------------------------------------------------------------------
# Author    Lee SangHyuk
# Date      2013. 1. 8 *
#===============================================================================

class Socket
  attr_reader :pdata
  attr_reader :IsConnected
  
  def self.init
    @pdata = ""
    @isConnected = false
  end
  
  def self.connect(ip, port)
    Network.connect(ip, port)
    @isConnected = true
  end  
  
  def self.send(data)
    return if not @isConnected
    json_data = JSON.encode(data)
    msg = "\0" * (json_data.size + 8)
    msg[0] = [json_data.size >> 24 & 0xff].pack('U*')
    msg[1] = [json_data.size >> 16 & 0xff].pack('U*')
    msg[2] = [json_data.size >>  8 & 0xff].pack('U*')
    msg[3] = [json_data.size       & 0xff].pack('U*')
    for i in 0...json_data.size
      msg[4+i] = json_data[i]
    end
    msg += "\n"
    Network.send(msg)
  end
  
  def self.close
    Network.close# if Network
  end
  
  def self.update
    return if not @isConnected
    if Network.ready?
      temp, plen = Network.recv(0xffff)
      @pdata = @pdata + temp[0...plen]
    end
    @pdata.gsub!("\u0000", "")
    while @pdata.size > 2
      sIndex = 0
      eIndex = 0
      for i in 0...@pdata.size
        if @pdata[i] == "{"
          sIndex = i
        end
        if @pdata[i] == "}"
          eIndex = i
          break
        end
      end
      if sIndex < eIndex
        data = @pdata[sIndex..eIndex]
        self.recv(JSON.decode(data))
      end
      @pdata = @pdata[(eIndex + (eIndex == 0 ? 0 : 1))...@pdata.size]
    end
  end
end