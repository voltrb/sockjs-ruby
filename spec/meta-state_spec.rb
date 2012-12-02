require 'meta-state'

describe MetaState::Machine do
  class TestMachine < described_class
    module DefaultMethods
      def c
      end
    end

    state :One do
      def a
        transition_to(:two)
      end

      include DefaultMethods
    end

    module Two
      def a
        transition_to(:one)
      end

      def b
        transition_to(:three)
      end
      include DefaultMethods
    end
    add_state(Two)

    state :Three do
      def a
        transition_to(:one)
      end

      def b
        transition_to(Two)
      end
      include DefaultMethods

      def c
        transition_to(One)
      end
    end
  end

  let :machine do
    TestMachine.new
  end

  it "should start in a state" do
    machine.current_state.should == TestMachine::One
  end

  it "should raise a WrongStateError for bad messages" do
    expect do
      machine.b
    end.to raise_error(MetaState::WrongStateError)
  end

  it "should transition between states" do
    machine.a
    machine.b
    machine.current_state.should == TestMachine::Three
  end

  it "should use included modules" do
    expect do
      machine.c
    end.not_to raise_error
  end

  it "should use overridden methods" do
    machine.a
    machine.b
    machine.c
    machine.current_state.should == TestMachine::One
  end
end
