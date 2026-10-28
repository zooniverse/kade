# frozen_string_literal: true

namespace :candidate_pool do
  desc 'Discover single-image candidates from Azure: candidate_pool:sync[context_id]'
  task :sync, [:context_id] => :environment do |_task, args|
    context = Context.find(args.fetch(:context_id))
    count = CandidatePool::SyncAzure.new(context).run.size
    puts "Discovered #{count} image subjects for context #{context.id}"
  end

  desc 'Export and submit a candidate prediction run: candidate_pool:predict[context_id]'
  task :predict, [:context_id] => :environment do |_task, args|
    context = Context.find(args.fetch(:context_id))
    raise ArgumentError, 'context must use azure_catalogue' unless context.azure_catalogue?

    PredictionManifestExportJob.new.perform(context.id)
  end
end
