FactoryGirl.define do
  sequence(:unique_string) {|n| "unique string #{n}" }
  
  factory :issue do
    summary { FactoryGirl.generate(:unique_string) }
    kind 'Defect'
    description { FactoryGirl.generate(:unique_string) }
  end
end