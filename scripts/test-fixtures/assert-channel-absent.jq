# FreeSWITCH omits rows entirely for an empty channel list. Require its explicit
# zero count rather than accepting arbitrary null/malformed responses as empty.
type == "object" and
if .row_count == 0 then
    (.rows == null or .rows == [])
else
    (.rows | type) == "array" and
    .row_count == (.rows | length) and
    all(.rows[]; (.uuid | type) == "string" and .uuid != $call)
end
