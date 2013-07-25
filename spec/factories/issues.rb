FactoryGirl.define do
  sequence(:unique_string) {|n| "unique string #{n}" }
  sequence(:unique_multi_line_string) { |n| "unique string #{n}\n\nsecond #{n} line\n\n  indented #{n} line"}
  
  factory :issue do
    summary { FactoryGirl.generate(:unique_string) }
    kind 'Defect'
    status 'Open'
    owner 'bobdole'
    priority 3
    
    description { FactoryGirl.generate(:unique_multi_line_string) }
  end
end