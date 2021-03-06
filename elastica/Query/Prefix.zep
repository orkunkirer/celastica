namespace Elastica\Query;

/**
 * Prefix query
 *
 * @package Elastica
 * @link http://www.elasticsearch.org/guide/reference/query-dsl/prefix-query.html
 */
class Prefix extends AbstractQuery
{
    /**
     * Constructs the Prefix query object
     *
     * @param array prefix OPTIONAL Calls setRawPrefix with the given prefix array
     */
    public function __construct(array prefix = []) -> void
    {
        this->setRawPrefix(prefix);
    }

    /**
     * setRawPrefix can be used instead of setPrefix if some more special
     * values for a prefix have to be set.
     *
     * @param  array                      prefix Prefix array
     * @return \Elastica\Query\Prefix Current object
     */
    public function setRawPrefix(array prefix) -> <\Elastica\Query\Prefix>
    {
        return this->setParams(prefix);
    }

    /**
     * Adds a prefix to the prefix query
     *
     * @param  string                     key   Key to query
     * @param  string|array               value Values(s) for the query. Boost can be set with array
     * @param  float                      boost OPTIONAL Boost value (default = 1.0)
     * @return \Elastica\Query\Prefix Current object
     */
    public function setPrefix(string key, var value, var boost = 1.0) -> <\Elastica\Query\Prefix>
    {
        var data = [];
        let data[key]["value"] = value;
        let data[key]["boost"] = boost;

        return this->setRawPrefix(data);
    }
}