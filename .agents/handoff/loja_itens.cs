using System.Collections.Generic;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("loja_itens", Version = "0.1.0", Resources = [typeof(Inventario), typeof(Item)])]
public class LojaItensExtension
{
    [ExoAction(Scope = "player")]
    public IReadOnlyList<Item> ListarItens() => ExoServices.Database.All<Item>();
}

[ExoResource("inventario", PrimaryKey = nameof(Id))]
public class Inventario
{
    [ExoColumn(Label = "ID", PrimaryKey = true)] public string Id { get; set; } = "";
    [ExoColumn(Label = "Ouro")] public int Ouro { get; set; }
    [ExoColumn(Label = "Itens")] public List<string> Itens { get; set; } = new();
}

[ExoResource("itens", PrimaryKey = nameof(Id))]
public class Item
{
    [ExoColumn(Label = "ID", PrimaryKey = true)] public string Id { get; set; } = "";
    [ExoColumn(Label = "Nome")] public string Nome { get; set; } = "";
    [ExoColumn(Label = "Tipo")] public string Tipo { get; set; } = "";
    [ExoColumn(Label = "Preco")] public int Preco { get; set; }
}
