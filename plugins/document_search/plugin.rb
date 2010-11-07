
Plugin.define do
  name    "document_search"
  version "1.0"
  file    "lib", "document_search"
  object  "DocumentSearch"
  dependencies "edit_view", ">0", "application_swt", ">0"
end