require 'spec_helper'

describe Bosh::Director::DeploymentPlan::AvailabilityZonePicker do
  subject(:zone_picker) { Bosh::Director::DeploymentPlan::AvailabilityZonePicker.new }
  let(:az1) { Bosh::Director::DeploymentPlan::AvailabilityZone.new('1', {}) }
  let(:az2) { Bosh::Director::DeploymentPlan::AvailabilityZone.new('2', {}) }
  let(:az3) { Bosh::Director::DeploymentPlan::AvailabilityZone.new('3', {}) }
  let(:deployment) { instance_double(BD::DeploymentPlan::Planner) }
  let(:job) { instance_double(BD::DeploymentPlan::Job, name: 'foo-job') }


  def desired_instance
    Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment)
  end

  def existing_instance_with_az(index, az, persistent_disks=[])
    instance_model = Bosh::Director::Models::Instance.make(index: index)
    allow(instance_model).to receive(:persistent_disks).and_return(persistent_disks)
    Bosh::Director::DeploymentPlan::InstanceWithAZ.new(instance_model, az)
  end

  describe 'placing and matching' do
    it 'a job in no zones with 3 instances, we expect two existing instances are reused and one new instance' do
      unmatched_desired_instances = [desired_instance, desired_instance, desired_instance]
      existing_0 = existing_instance_with_az(0, nil)
      existing_1 = existing_instance_with_az(1, nil)
      unmatched_existing_instances = [existing_0, existing_1]

      azs = []
      results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

      expect(results[:desired_existing]).to match_array([
            {existing_instance_model: existing_0.model, desired_instance: unmatched_desired_instances[0]},
            {existing_instance_model: existing_1.model, desired_instance: unmatched_desired_instances[1]}
          ])

      expect(results[:desired_new]).to match_array([Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, nil, false, 2)])

      expect(results[:obsolete]).to eq([])
    end

    it 'a job in nil zones with 3 instances, we expect two existing instances are reused and one new instance' do
      unmatched_desired_instances = [desired_instance, desired_instance, desired_instance]
      existing_0 = existing_instance_with_az(0, nil, ['disk-blah'])
      existing_1 = existing_instance_with_az(1, nil)
      unmatched_existing_instanaces = [existing_0, existing_1]

      azs = nil
      results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instanaces)

      expect(results[:desired_existing]).to match_array([
            {existing_instance_model: existing_0.model, desired_instance: unmatched_desired_instances[0]},
            {existing_instance_model: existing_1.model, desired_instance: unmatched_desired_instances[1]}
      ])

      expect(results[:desired_new]).to match_array([Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, nil, false, 2)])

      expect(results[:obsolete]).to eq([])
    end

    it 'a job in 2 zones with 3 instances, we expect all instances will be new' do
      unmatched_desired_instances = [desired_instance, desired_instance, desired_instance]
      unmatched_existing_instances = []

      azs = [az1, az2]
      results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

      expect(results[:desired_existing]).to match_array([])
      expect(results[:desired_new]).to match_array([
            Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az1, false, 0),
            Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az2, false, 1),
            Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az1, false, 2)])
      expect(results[:obsolete]).to eq([])
    end

    describe 'scaling down' do
      it 'prefers lower indexed existing instances' do
        unmatched_desired_instances = [desired_instance]
        existing_0 = existing_instance_with_az(0, nil)
        existing_1 = existing_instance_with_az(1, nil)
        unmatched_existing_instances = [existing_1, existing_0]

        azs = []
        results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

        expect(results[:desired_existing]).to eq([
              {existing_instance_model: existing_0.model, desired_instance: unmatched_desired_instances[0]},
            ])

        expect(results[:desired_new]).to eq([])

        expect(results[:obsolete]).to eq([existing_1.model])
      end
    end

    describe 'indexes' do
      context 'when several existing instances have same index (migration)' do
        it 're-assignes indexes properly' do
          unmatched_desired_instances = [desired_instance, desired_instance]
          existing_0 = existing_instance_with_az(1, nil)
          existing_1 = existing_instance_with_az(1, nil)
          unmatched_existing_instances = [existing_1, existing_0]

          azs = []
          results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

          new_indexes = []
          new_indexes << results[:desired_existing][0][:existing_instance_model].index
          new_indexes << results[:desired_existing][1][:existing_instance_model].index
          expect(new_indexes).to match_array([0, 1])

          expect(results[:desired_new]).to eq([])

          expect(results[:obsolete]).to eq([])
        end
      end
    end

    describe 'when a job is deployed in 2 zones with 3 existing instances, and re-deployed into one zone' do
      it 'should match the 2 existing instances from the desired zone to 2 of the desired instances' do
        unmatched_desired_instances = [desired_instance, desired_instance, desired_instance]

        existing_zone1_2 = existing_instance_with_az(2, '1')
        existing_zone1_0 = existing_instance_with_az(0, '1')
        existing_zone2_1 = existing_instance_with_az(1, '2')
        unmatched_existing_instances = [existing_zone1_0, existing_zone1_2, existing_zone2_1]

        azs = [az1]
        results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

        expect(results[:desired_existing]).to match_array([
              {existing_instance_model: existing_zone1_0.model, desired_instance: unmatched_desired_instances[0]},
              {existing_instance_model: existing_zone1_2.model, desired_instance: unmatched_desired_instances[1]}
              ])

        expect(results[:desired_new]).to match_array([
              Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az1, false, 3)])

        expect(results[:obsolete]).to match_array([existing_zone2_1.model])
      end
    end

    describe 'when a job is deployed in 2 zones with 5 existing instances, and re-deployed into 3 zones' do
      it 'should match the 2 existing instances from the 2 desired zones' do
        unmatched_desired_instances = [
          desired_instance,
          desired_instance,
          desired_instance,
          desired_instance,
          desired_instance,
        ]

        existing_zone1_0 = existing_instance_with_az(0, '1')
        existing_zone1_1 = existing_instance_with_az(1, '1')
        existing_zone1_2 = existing_instance_with_az(2, '1')
        existing_zone2_3 = existing_instance_with_az(3, '2')
        existing_zone2_4 = existing_instance_with_az(4, '2')

        unmatched_existing_instances = [existing_zone1_0, existing_zone1_1, existing_zone1_2, existing_zone2_3, existing_zone2_4]

        azs = [az1, az2, az3]
        results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

        expect(results[:desired_existing].map{ |i| i[:existing_instance_model] }).to contain_exactly(
              existing_zone1_0.model,
              existing_zone1_1.model,
              existing_zone2_3.model,
              existing_zone2_4.model
            )

        expect(results[:desired_new]).to match_array([
              Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az3, false, 5)])

        expect(results[:obsolete]).to match_array([existing_zone1_2.model])
      end
    end

    describe 'when a job is deployed in 2 zones with 3 existing instances, and re-deployed into 3 zones with 4 instances' do
      it 'uses the zone with 2 existing instances as the zone with the extra instance' do
        unmatched_desired_instances = [
          desired_instance,
          desired_instance,
          desired_instance,
          desired_instance,
        ]

        existing_zone1_0 = existing_instance_with_az(0, '1')
        existing_zone2_0 = existing_instance_with_az(1, '2')
        existing_zone2_2 = existing_instance_with_az(2, '2')

        unmatched_existing_instances = [existing_zone1_0, existing_zone2_0, existing_zone2_2]

        azs = [az1, az2, az3]
        results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

        expect(results[:desired_existing].map{ |i| i[:existing_instance_model] }).to match_array([
              existing_zone1_0.model,
              existing_zone2_0.model,
              existing_zone2_2.model
            ])

        expect(results[:desired_new]).to match_array([
              Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az3, false, 3)])
        expect(results[:obsolete]).to match_array([])
      end
    end

    describe 'when existing instances have persistent disk' do
      describe 'when existing instances have no az, and desired have no azs' do
        it 'should not recreate the instances' do
          existing_0 = existing_instance_with_az(0, nil, [Bosh::Director::Models::PersistentDisk.make])
          unmatched_desired_instances = [desired_instance, desired_instance]
          results = zone_picker.place_and_match_in([], unmatched_desired_instances, [existing_0])

          expect(results[:desired_existing]).to match_array([
                {existing_instance_model: existing_0.model, desired_instance: unmatched_desired_instances[0]}
              ])
          expect(results[:desired_new]).to match_array([
                Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, nil, false, 1)])
          expect(results[:obsolete]).to match_array([])
        end
      end

      describe 'with the same number of desired instances both in the same zone' do
        it 'should not move existing instances' do
          existing_zone1_0 = existing_instance_with_az(0, '1', [Bosh::Director::Models::PersistentDisk.make])
          existing_zone1_1 = existing_instance_with_az(1, '1', [Bosh::Director::Models::PersistentDisk.make])

          unmatched_desired_instances = [desired_instance, desired_instance]
          results = zone_picker.place_and_match_in([az1, az2], unmatched_desired_instances, [existing_zone1_0, existing_zone1_1])

          expect(results[:desired_existing]).to match_array([
                {existing_instance_model: existing_zone1_0.model, desired_instance: unmatched_desired_instances[0]},
                {existing_instance_model: existing_zone1_1.model, desired_instance: unmatched_desired_instances[1]}
              ])

          expect(results[:desired_new]).to match_array([])
          expect(results[:obsolete]).to match_array([])
        end
      end

      describe 'when the existing instance is not in the set of desired azs' do
        it 'should not reuse the existing instance' do
          unmatched_desired_instances = [desired_instance, desired_instance]

          existing_zone1_0 = existing_instance_with_az(0, '1', ['disk0'])
          existing_zone66_1 = existing_instance_with_az(1, '66', ['disk1'])
          unmatched_existing_instances = [existing_zone1_0, existing_zone66_1]

          azs = [az1, az2]
          results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

          expect(results[:desired_existing]).to match_array([
                {existing_instance_model: existing_zone1_0.model, desired_instance: unmatched_desired_instances[1]}
              ])
          expect(results[:desired_new]).to match_array([
                Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az2, false, 2)
              ])
          expect(results[:obsolete]).to match_array([existing_zone66_1.model])

        end
      end

      describe 'when existing instances have persistent disk, no az, and are assigned an az' do
        xit 'should talk to dmitiry' do
          #not clear what should happen here. We're going to defer a decision until the 'migrated_jobs' story set.
        end
      end

      describe "when none of instances' persistent disks are active" do
        it 'should not destroy/remove/re-balance them, should do nothing' do
          existing_zone1_0 = existing_instance_with_az(0, '1', [Bosh::Director::Models::PersistentDisk.make(active: false)])
          existing_zone1_1 = existing_instance_with_az(1, '1', [Bosh::Director::Models::PersistentDisk.make(active: false)])

          unmatched_desired_instances = [desired_instance, desired_instance]
          results = zone_picker.place_and_match_in([az1, az2], unmatched_desired_instances, [existing_zone1_0, existing_zone1_1])

          expect(results[:desired_existing]).to match_array([
                {existing_instance_model: existing_zone1_0.model, desired_instance: unmatched_desired_instances[0]},
                {existing_instance_model: existing_zone1_1.model, desired_instance: unmatched_desired_instances[1]}
               ])

          expect(results[:desired_new]).to match_array([])
          expect(results[:obsolete]).to match_array([])
        end
      end

      describe 'and some existing instances have no persistent disks' do
        it 'should re-balance the instance that never had persistent disk' do
          existing_zone1_0 = existing_instance_with_az(0, '1')
          existing_zone1_1 = existing_instance_with_az(1, '1', [Bosh::Director::Models::PersistentDisk.make(active: false)])

          unmatched_desired_instances = [desired_instance, desired_instance]
          results = zone_picker.place_and_match_in([az1, az2], unmatched_desired_instances, [existing_zone1_0, existing_zone1_1])

          expect(results[:desired_existing]).to match_array([
                {existing_instance_model: existing_zone1_1.model, desired_instance: unmatched_desired_instances[1]}])
          expect(results[:desired_new]).to match_array([
                Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az2, false, 2)])
          expect(results[:obsolete]).to match_array([existing_zone1_0.model])
        end
      end

      describe 'where 2 or more existing instances in the same AZ with persistent disk and scale down to 1' do
        it 'should eliminate one of the instances' do
          existing_zone1_0 = existing_instance_with_az(0, '1', [Bosh::Director::Models::PersistentDisk.make(active: true)])
          existing_zone1_1 = existing_instance_with_az(1, '1', [Bosh::Director::Models::PersistentDisk.make(active: false)])

          unmatched_desired_instances = [desired_instance]
          unmatched_existing_instances = [existing_zone1_0, existing_zone1_1]

          results = zone_picker.place_and_match_in([az1], unmatched_desired_instances, unmatched_existing_instances)

          expect(results[:desired_existing]).to match_array([
                {existing_instance_model: existing_zone1_0.model, desired_instance: unmatched_desired_instances[0]}
                ])
          expect(results[:desired_new]).to match_array([])
          expect(results[:obsolete]).to match_array([existing_zone1_1.model])

        end
      end

      describe 'when an az that has instances with persistent disks is removed' do
        it 'should re-balance the instances across the remaining azs' do
          existing_zone1_0 = existing_instance_with_az(0, '1', [Bosh::Director::Models::PersistentDisk.make])
          existing_zone1_1 = existing_instance_with_az(1, '1', [Bosh::Director::Models::PersistentDisk.make])
          existing_zone2_2 = existing_instance_with_az(2, '2', [Bosh::Director::Models::PersistentDisk.make])
          existing_zone2_3 = existing_instance_with_az(3, '2', [Bosh::Director::Models::PersistentDisk.make])
          existing_zone3_4 = existing_instance_with_az(4, '3', [Bosh::Director::Models::PersistentDisk.make])
          existing_zone3_5 = existing_instance_with_az(5, '3', [Bosh::Director::Models::PersistentDisk.make])

          unmatched_desired_instances = [desired_instance, desired_instance, desired_instance, desired_instance, desired_instance, desired_instance]
          unmatched_existing_instances = [existing_zone1_0, existing_zone1_1, existing_zone2_2, existing_zone2_3, existing_zone3_4, existing_zone3_5]
          results = zone_picker.place_and_match_in([az1, az2], unmatched_desired_instances, unmatched_existing_instances)

          expect(results[:desired_existing].map{ |i| i[:existing_instance_model] }).to match_array([
                existing_zone1_0.model,
                existing_zone1_1.model,
                existing_zone2_2.model,
                existing_zone2_3.model ])
          expect(results[:desired_new]).to match_array([
                Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az1, false, 6),
                Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az2, false, 7),
              ])
          expect(results[:obsolete]).to match_array([existing_zone3_4.model, existing_zone3_5.model])
        end
      end

      describe 'with one additional desired instance' do
        it 'should add the instance to the additional az' do
          unmatched_desired_instances = [desired_instance, desired_instance, desired_instance]

          existing_zone1_0 = existing_instance_with_az(0, '1', ['disk0'])
          existing_zone1_1 = existing_instance_with_az(1, '1', ['disk1'])
          unmatched_existing_instances = [existing_zone1_0, existing_zone1_1]

          azs = [az1, az2]
          results = zone_picker.place_and_match_in(azs, unmatched_desired_instances, unmatched_existing_instances)

          expect(results[:desired_existing].map{ |i| i[:existing_instance_model] }).to match_array([
                existing_zone1_0.model,
                existing_zone1_1.model ])
          expect(results[:desired_new]).to match_array([
                Bosh::Director::DeploymentPlan::DesiredInstance.new(job, 'started', deployment, az2, false, 2)
              ])
          expect(results[:obsolete]).to match_array([])
        end
      end
    end
  end
end
