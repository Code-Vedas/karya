# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
threads_count = ENV.fetch('RAILS_MAX_THREADS', 3)
threads threads_count, threads_count

port ENV.fetch('PORT', 3000)

plugin :tmp_restart
