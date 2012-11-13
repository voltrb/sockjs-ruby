shared_context "Transport", :type => :transport do
  let(:connection) do
    SockJS::Connection.new {}
  end

  let(:open_request) do
    FakeRequest.new.tap do |req|
      req.data = ""
    end
  end

  let(:session) do
    FakeSession.new({:open => []}).tap do |session|
      session.receive_request(open_request, prior_transport)
      session.check_status
    end
  end

  let(:existing_session_key) do
    "b"
  end


  let(:transport) do
    if self.respond_to?(:prior_transport)
      connection.sessions[existing_session_key] = session
    end
    described_class.new(connection, {})
  end

  let(:response) do
    transport.handle(request)
  end
end

shared_context "Needs EventMachine", :em => true do
  around :each do |example|
    EM.run{
      example.run
      EM.stop
    }
  end
end
