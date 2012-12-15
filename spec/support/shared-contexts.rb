shared_context "Transport", :type => :transport do
  let(:connection) do
    SockJS::Connection.new(SockJS::Session)
  end

  let(:open_request) do
    FakeRequest.new.tap do |req|
      req.data = ""
    end
  end

  let(:existing_session_key) do
    "b"
  end

  let(:session) do
    connection.create_session(existing_session_key)
  end

  let :transport_options do
    {}
  end

  let(:transport) do
    described_class.new(connection, transport_options)
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
