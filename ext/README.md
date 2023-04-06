### Custom Values

when there is `ext/<table_name>.rb`. KaminariOkoshi is used by prepending

#### Sample

```
require 'faker'

module Users
  def first_name(type, limit, name)
    quote(Faker::Name.last_name)
  end
end
```

#### description

```
module <TableName>
  def <column_name>(type, limit, name)
    any return
  end
end
```

Always takes type, limit and name as arguments  
use quotes where necessary
