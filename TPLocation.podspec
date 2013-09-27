Pod::Spec.new do |s|
  s.name         = "TPLocation"
  s.version      = "1.0.0"
  s.summary      = "A simple asynchronous location library for iOS."
  s.description  = <<-DESC
TPLocation provides a completion-block-style asynchronous location interface to the CLLocationManager library.
                      DESC
  s.homepage     = "https://github.com/tetherpad/TPLocation"
  s.license      = 'MIT'
  s.authors      = { "Jen Leech" => "jen@tetherpad.com", "Mark Ferlatte" => "mark@tetherpad.com" }
  s.source       = { 
    :git => "git@github.com:tetherpad/TPLocation.git", 
    :tag => "1.0.0"
  }
  s.source_files = 'TPLocationManager.{h,m}'
  s.requires_arc = true

  s.ios.deployment_target = '6.0'
  s.osx.deployment_target = '10.7'
end
