require 'spec_helper'

describe Appsignal::Transmitter do
  let(:_80beans_) { 'http://www.80beans.com' }
  let(:action) { 'action' }
  let(:klass) { Appsignal::Transmitter }
  let(:instance) { klass.new(_80beans_, action, :the_api_key) }
  subject { instance }

  describe "#uri" do
    it "returns uri" do
      subject.uri.should == URI("http://www.80beans.com/action")
    end
  end

  describe "#transmit" do
    let(:http_client) { stub(:request => stub(:code => '200')) }
    before { instance.stub(:encoded_message => :the_message) }
    before { instance.stub(:http_client => http_client) }

    subject { instance.transmit(:shipit => :payload) }

    it { should == '200' }
  end

  describe "#encoded_message" do
    it "calls message" do
      JSON.stub(:generate => "{a:'b'}")
      subject.should_receive(:message).with(:payload => "{a:'b'}")
    end

    it "encodes the payload using json" do
      subject.stub(:message)
      JSON.should_receive(:generate).with({"a" => "b"})
    end

    after { subject.encoded_message(:payload => {'a' => 'b'}) }
  end

  describe "#message" do
    it "calls Net::HTTP.post_form with the correct params" do
      post = stub
      post.should_receive(:set_form_data).with(
        :api_key => :the_api_key,
        :gem_version => Appsignal::VERSION,
        :the => :payload
      )
      Net::HTTP::Post.should_receive(:new).with('/action').and_return(post)
      instance.message(:the => :payload)
    end
  end

  describe "ca_file_path" do
    subject { instance.send(:ca_file_path) }

    it { should include('resources/thawte_primary_root_ca.pem') }
    it("should exist") { File.exists?(subject).should be_true }
  end

  describe "#http_client" do
    subject { instance.send(:http_client) }

    context "with a http uri" do
      it { should be_instance_of(Net::HTTP) }

      its(:use_ssl?) { should be_false }
    end

    context "with a https uri" do
      let(:instance) { klass.new('https://www.80beans.com', action, :the_api_key) }

      its(:use_ssl?) { should be_true }
      its(:verify_mode) { should == OpenSSL::SSL::VERIFY_PEER }
      its(:ca_file) { include('resources/thawte_primary_root_ca.pem') }
    end
  end
end