# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Karya::JobLifecycle::Constants' do
  let(:constants_module) { Karya::JobLifecycle.const_get(:Constants, false) }

  describe 'lifecycle state constants' do
    it 'defines SUBMISSION state' do
      expect(constants_module::SUBMISSION).to eq(:submission)
    end

    it 'defines QUEUED state' do
      expect(constants_module::QUEUED).to eq(:queued)
    end

    it 'defines RESERVED state' do
      expect(constants_module::RESERVED).to eq(:reserved)
    end

    it 'defines RUNNING state' do
      expect(constants_module::RUNNING).to eq(:running)
    end

    it 'defines SUCCEEDED state' do
      expect(constants_module::SUCCEEDED).to eq(:succeeded)
    end

    it 'defines FAILED state' do
      expect(constants_module::FAILED).to eq(:failed)
    end

    it 'defines RETRY_PENDING state' do
      expect(constants_module::RETRY_PENDING).to eq(:retry_pending)
    end

    it 'defines DEAD_LETTER state' do
      expect(constants_module::DEAD_LETTER).to eq(:dead_letter)
    end

    it 'defines CANCELLED state' do
      expect(constants_module::CANCELLED).to eq(:cancelled)
    end
  end

  describe 'STATES' do
    it 'includes all canonical states in order' do
      expect(constants_module::STATES).to eq(%i[
                                               submission
                                               queued
                                               reserved
                                               running
                                               succeeded
                                               failed
                                               retry_pending
                                               dead_letter
                                               cancelled
                                             ])
    end

    it 'is frozen' do
      expect(constants_module::STATES).to be_frozen
    end
  end

  describe 'TRANSITIONS' do
    it 'defines valid transitions from submission' do
      expect(constants_module::TRANSITIONS[:submission]).to eq([:queued])
    end

    it 'defines valid transitions from queued' do
      expect(constants_module::TRANSITIONS[:queued]).to contain_exactly(:reserved, :dead_letter, :cancelled)
    end

    it 'defines valid transitions from reserved' do
      expect(constants_module::TRANSITIONS[:reserved]).to contain_exactly(:running, :queued, :dead_letter, :cancelled)
    end

    it 'defines valid transitions from running' do
      expect(constants_module::TRANSITIONS[:running]).to contain_exactly(:queued, :succeeded, :failed, :dead_letter, :cancelled)
    end

    it 'defines valid transitions from succeeded' do
      expect(constants_module::TRANSITIONS[:succeeded]).to eq([])
    end

    it 'defines valid transitions from failed' do
      expect(constants_module::TRANSITIONS[:failed]).to contain_exactly(:retry_pending, :dead_letter)
    end

    it 'defines valid transitions from retry_pending' do
      expect(constants_module::TRANSITIONS[:retry_pending]).to contain_exactly(:queued, :dead_letter, :cancelled)
    end

    it 'defines valid transitions from dead_letter' do
      expect(constants_module::TRANSITIONS[:dead_letter]).to contain_exactly(:queued, :retry_pending, :cancelled)
    end

    it 'defines valid transitions from cancelled' do
      expect(constants_module::TRANSITIONS[:cancelled]).to eq([])
    end

    it 'is frozen' do
      expect(constants_module::TRANSITIONS).to be_frozen
    end

    it 'has frozen transition arrays' do
      constants_module::TRANSITIONS.each_value do |transitions|
        expect(transitions).to be_frozen
      end
    end
  end

  describe 'TERMINAL_STATES' do
    it 'includes only succeeded and cancelled' do
      expect(constants_module::TERMINAL_STATES).to contain_exactly(:succeeded, :cancelled)
    end

    it 'is frozen' do
      expect(constants_module::TERMINAL_STATES).to be_frozen
    end
  end

  describe 'EMPTY_TRANSITIONS' do
    it 'is an empty frozen array' do
      expect(constants_module::EMPTY_TRANSITIONS).to eq([])
      expect(constants_module::EMPTY_TRANSITIONS).to be_frozen
    end
  end

  describe 'CANONICAL_STATE_NAMES' do
    it 'contains string versions of all states' do
      expect(constants_module::CANONICAL_STATE_NAMES).to contain_exactly(
        'submission', 'queued', 'reserved', 'running',
        'succeeded', 'failed', 'retry_pending', 'dead_letter', 'cancelled'
      )
    end

    it 'is frozen' do
      expect(constants_module::CANONICAL_STATE_NAMES).to be_frozen
    end
  end

  describe 'CANONICAL_TERMINAL_STATE_NAMES' do
    it 'contains string versions of terminal states' do
      expect(constants_module::CANONICAL_TERMINAL_STATE_NAMES).to contain_exactly('succeeded', 'cancelled')
    end

    it 'is frozen' do
      expect(constants_module::CANONICAL_TERMINAL_STATE_NAMES).to be_frozen
    end
  end

  describe 'CANONICAL_TRANSITION_NAMES' do
    it 'has string keys and string value arrays' do
      constants_module::CANONICAL_TRANSITION_NAMES.each do |from_state, to_states|
        expect(from_state).to be_a(String)
        expect(to_states).to be_an(Array)
        expect(to_states).to all(be_a(String))
      end
    end

    it 'is frozen' do
      expect(constants_module::CANONICAL_TRANSITION_NAMES).to be_frozen
    end

    it 'has frozen value arrays' do
      constants_module::CANONICAL_TRANSITION_NAMES.each_value do |transitions|
        expect(transitions).to be_frozen
      end
    end
  end

  describe 'MAX_STATE_NAME_LENGTH' do
    it 'is set to 64' do
      expect(constants_module::MAX_STATE_NAME_LENGTH).to eq(64)
    end
  end
end
